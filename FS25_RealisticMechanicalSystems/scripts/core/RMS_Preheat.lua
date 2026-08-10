RMS_Preheat = RMS_Preheat or {}

RMS_Preheat.STATE = {
    IDLE = 0,
    IGNITION = 1,
    PREHEATING = 2,
    READY = 3,
    FAILED = 4
}

RMS_Preheat.STATE_NAME = {
    [RMS_Preheat.STATE.IDLE] = "IDLE",
    [RMS_Preheat.STATE.IGNITION] = "IGNITION",
    [RMS_Preheat.STATE.PREHEATING] = "PREHEATING",
    [RMS_Preheat.STATE.READY] = "READY",
    [RMS_Preheat.STATE.FAILED] = "FAILED"
}

function RMS_Preheat.getEngineTemperatureC(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local engineTemperature = spec ~= nil and tonumber(spec.rawEngineTemperature or spec.engineTemperature) or nil
    local environmentTemperature = RMS_Electrical.getEnvironmentTemperatureC()

    if engineTemperature == nil or engineTemperature <= -90 then
        return environmentTemperature
    end

    return RealisticMechanicalSystems.sanitizeNumber(engineTemperature, environmentTemperature, -80, 160)
end

local function setState(vehicle, state)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    spec.preheatState = state
end

function RMS_Preheat.getGlowPlugFailureSeverity(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_FAILURE or nil
    return math.floor(RealisticMechanicalSystems.sanitizeNumber(effect ~= nil and effect.value or 0, 0, 0, 4))
end

function RMS_Preheat.initSpec(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    spec.preheatState = RMS_Preheat.STATE.IDLE
    spec.preheatLampTestActive = false
    spec.preheatLampTestRemainingMs = 0
    spec.preheatRemainingMs = 0
    spec.preheatRequiredMs = 0
    spec.preheatWasRequired = false
    spec.preheatAutomaticCrank = false
    spec.preheatAutomaticCrankElapsedMs = 0
    spec.preheatColdStartFaultSeverity = 0
    spec.glowPlugColdIdleRpmBackup = nil
    spec._lastPreheatUxState = RMS_Preheat.STATE.IDLE
end

function RMS_Preheat.getStateName(state)
    return RMS_Preheat.STATE_NAME[state] or "UNKNOWN"
end

function RMS_Preheat.isDieselVehicle(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec ~= nil and spec.isDieselVehicle ~= nil then
        return spec.isDieselVehicle
    end

    local motorizedSpec = vehicle ~= nil and vehicle.spec_motorized or nil
    if motorizedSpec == nil then
        return false
    end

    return motorizedSpec.consumersByFillType ~= nil
        and motorizedSpec.consumersByFillType[FillType.DIESEL] ~= nil
end

function RMS_Preheat.getRequiredDurationMs(vehicle)
    if not RMS_Preheat.isDieselVehicle(vehicle) then
        return 0
    end

    local curve = RMS_Config.PREHEAT.WAIT_TIME_CURVE
    local engineTemperature = RMS_Preheat.getEngineTemperatureC(vehicle)

    if engineTemperature >= RMS_Config.PREHEAT.ACTIVATION_TEMPERATURE_C then
        return 0
    end

    if engineTemperature <= curve[1][1] then
        return curve[1][2]
    end

    for index = 2, #curve do
        local previousPoint = curve[index - 1]
        local currentPoint = curve[index]
        if engineTemperature <= currentPoint[1] then
            local temperatureRange = currentPoint[1] - previousPoint[1]
            if temperatureRange <= 0 then
                return currentPoint[2]
            end

            local alpha = (engineTemperature - previousPoint[1]) / temperatureRange
            return math.max(math.floor(previousPoint[2] + (currentPoint[2] - previousPoint[2]) * alpha + 0.5), 0)
        end
    end

    return 0
end

function RMS_Preheat.isHeating(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and spec.preheatState == RMS_Preheat.STATE.PREHEATING
end

function RMS_Preheat.isLampTestActive(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and spec.preheatLampTestActive == true
end

function RMS_Preheat.isAutomaticCrankActive(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and spec.preheatAutomaticCrank == true
end

function RMS_Preheat.isFailed(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and spec.preheatState == RMS_Preheat.STATE.FAILED
end

function RMS_Preheat.onCrankPassed(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    spec.preheatAutomaticCrank = false
end

function RMS_Preheat.shouldApplyGlowPlugHardStart(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.preheatState ~= RMS_Preheat.STATE.READY then
        return false
    end

    return spec.preheatWasRequired == true and RMS_Preheat.getGlowPlugFailureSeverity(vehicle) > 0
end

function RMS_Preheat.requestStart(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle or not RMS_Preheat.isDieselVehicle(vehicle) then
        return false
    end

    if vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then
        return false
    end

    local currentMotorState = vehicle.getMotorState ~= nil and vehicle:getMotorState() or MotorState.OFF
    if currentMotorState == MotorState.STARTING or currentMotorState == MotorState.ON then
        return false
    end

    if spec.preheatState == RMS_Preheat.STATE.FAILED then
        RMS_Preheat.reset(vehicle, false)
        if vehicle.setMotorState ~= nil then
            vehicle:setMotorState(MotorState.OFF)
        end
        return false
    end

    if spec.preheatState == RMS_Preheat.STATE.IGNITION
        or spec.preheatState == RMS_Preheat.STATE.PREHEATING
        or spec.preheatState == RMS_Preheat.STATE.READY then
        return true
    end

    local requiredDurationMs = RMS_Preheat.getRequiredDurationMs(vehicle)
    spec.preheatLampTestRemainingMs = RMS_Config.PREHEAT.LAMP_TEST_DURATION_MS
    spec.preheatLampTestActive = spec.preheatLampTestRemainingMs > 0
    spec.preheatRemainingMs = requiredDurationMs
    spec.preheatRequiredMs = requiredDurationMs
    spec.preheatWasRequired = requiredDurationMs > 0
    spec.preheatAutomaticCrank = false
    spec.preheatAutomaticCrankElapsedMs = 0
    spec.preheatColdStartFaultSeverity = 0

    if requiredDurationMs > 0 then
        setState(vehicle, RMS_Preheat.STATE.PREHEATING)
    else
        setState(vehicle, RMS_Preheat.STATE.IGNITION)
    end

    if vehicle.getMotorState ~= nil and vehicle.setMotorState ~= nil and currentMotorState == MotorState.OFF then
        vehicle:setMotorState(MotorState.IGNITION)
    end

    return true
end

function RMS_Preheat.reset(vehicle, preserveColdStartFault)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    spec.preheatState = RMS_Preheat.STATE.IDLE
    spec.preheatLampTestActive = false
    spec.preheatLampTestRemainingMs = 0
    spec.preheatRemainingMs = 0
    spec.preheatRequiredMs = 0
    spec.preheatWasRequired = false
    spec.preheatAutomaticCrank = false
    spec.preheatAutomaticCrankElapsedMs = 0

    if not preserveColdStartFault then
        spec.preheatColdStartFaultSeverity = 0
    end
end

function RMS_Preheat.shouldBlockMotorRun(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle or not RMS_Preheat.isDieselVehicle(vehicle) then
        return false
    end

    local motorState = vehicle:getMotorState()
    if motorState == MotorState.STARTING or motorState == MotorState.ON then
        return false
    end

    local state = spec.preheatState or RMS_Preheat.STATE.IDLE
    if state == RMS_Preheat.STATE.IGNITION
        or state == RMS_Preheat.STATE.PREHEATING
        or state == RMS_Preheat.STATE.FAILED then
        return true
    end

    if state == RMS_Preheat.STATE.READY then
        return false
    end

    local ignitionStartRequested = g_ignitionLockManager ~= nil
        and g_ignitionLockManager:getIsAvailable()
        and g_ignitionLockManager:getState() == IgnitionLockState.START

    if ignitionStartRequested then
        RMS_Preheat.requestStart(vehicle)
        return true
    end

    return false
end

function RMS_Preheat.shouldDeferStart(vehicle, passed)
    if not vehicle.isServer or passed or not RMS_Preheat.isDieselVehicle(vehicle) then
        return false
    end

    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle or spec.preheatState == RMS_Preheat.STATE.READY then
        return false
    end

    RMS_Preheat.requestStart(vehicle)
    return true
end

function RMS_Preheat.updateClientUx(vehicle)
    if not vehicle.isClient then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local state = spec.preheatState or RMS_Preheat.STATE.IDLE
    local previousState = spec._lastPreheatUxState
    if previousState == state then
        return
    end

    spec._lastPreheatUxState = state
    if not vehicle:getIsActiveForInput(true)
        or RMS_Config.CORE.ENABLE_WARNING_MESSAGES == false then
        return
    end

    if state == RMS_Preheat.STATE.PREHEATING then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_preheat_ignition_message"), 2000)
    elseif state == RMS_Preheat.STATE.FAILED then
        local messageKey = spec.preheatWasRequired and RMS_Preheat.getGlowPlugFailureSeverity(vehicle) >= 4
            and "rms_preheat_system_failure_message"
            or "rms_preheat_start_failed_message"
        g_currentMission:showBlinkingWarning(g_i18n:getText(messageKey), 4000)
    end
end

function RMS_Preheat.update(vehicle, dt)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    RMS_Preheat.updateClientUx(vehicle)

    if not vehicle.isServer then
        return
    end

    local motorState = vehicle.getMotorState ~= nil and vehicle:getMotorState() or MotorState.OFF
    if motorState == MotorState.STARTING or motorState == MotorState.ON then
        local coldThreshold = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
        local preserveColdStartFault = motorState == MotorState.STARTING
            or RMS_Preheat.getEngineTemperatureC(vehicle) < coldThreshold
        RMS_Preheat.reset(vehicle, preserveColdStartFault)
        return
    end

    if motorState == MotorState.OFF then
        if spec.preheatState ~= RMS_Preheat.STATE.IDLE then
            RMS_Breakdowns.cancelStarterCranking(vehicle)
        end
        RMS_Preheat.reset(vehicle, false)
        return
    end

    if spec.preheatState == RMS_Preheat.STATE.IGNITION or spec.preheatState == RMS_Preheat.STATE.PREHEATING then
        spec.preheatLampTestRemainingMs = math.max((spec.preheatLampTestRemainingMs or 0) - dt, 0)
        spec.preheatLampTestActive = spec.preheatLampTestRemainingMs > 0

        if spec.preheatState == RMS_Preheat.STATE.PREHEATING then
            spec.preheatRemainingMs = math.max((spec.preheatRemainingMs or 0) - dt, 0)
        end

        if spec.preheatLampTestRemainingMs <= 0 and spec.preheatRemainingMs <= 0 then
            local failureSeverity = RMS_Preheat.getGlowPlugFailureSeverity(vehicle)
            spec.preheatColdStartFaultSeverity = spec.preheatWasRequired and failureSeverity or 0
            spec.preheatAutomaticCrank = true
            spec.preheatAutomaticCrankElapsedMs = 0
            setState(vehicle, RMS_Preheat.STATE.READY)
            vehicle:startMotor(false)
        end
    elseif spec.preheatState == RMS_Preheat.STATE.READY and spec.preheatAutomaticCrank then
        spec.preheatAutomaticCrankElapsedMs = (spec.preheatAutomaticCrankElapsedMs or 0) + dt
        if spec.preheatAutomaticCrankElapsedMs >= RMS_Config.PREHEAT.MAX_AUTOMATIC_CRANK_MS then
            spec.preheatAutomaticCrank = false
            RMS_Breakdowns.cancelStarterCranking(vehicle)
            setState(vehicle, RMS_Preheat.STATE.FAILED)
        end
    end
end
