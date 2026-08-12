RMS_Exhaust = RMS_Exhaust or {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function lerp(startValue, endValue, alpha)
    return startValue + (endValue - startValue) * alpha
end

local function getNumber(value, defaultValue, minimum, maximum)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        number = defaultValue
    end
    if minimum ~= nil then
        number = math.max(number, minimum)
    end
    if maximum ~= nil then
        number = math.min(number, maximum)
    end

    return number
end

local function getRamp(value, from, to)
    if to <= from then
        return value >= to and 1 or 0
    end

    return clamp((value - from) / (to - from), 0, 1)
end

function RMS_Exhaust.getEraFactor(year)
    local factors = RMS_Config.EXHAUST.ERA_FACTORS
    local resolvedYear = getNumber(year, RMS_VehicleYears ~= nil and RMS_VehicleYears.DEFAULT_YEAR or 2000)
    for _, entry in ipairs(factors) do
        if resolvedYear < entry[1] then
            return entry[2]
        end
    end

    return factors[#factors][2]
end

function RMS_Exhaust.getIsStageV(year, peakPowerKw)
    local config = RMS_Config.EXHAUST.STAGE_V
    local resolvedYear = getNumber(year, RMS_VehicleYears ~= nil and RMS_VehicleYears.DEFAULT_YEAR or 2000)
    local power = getNumber(peakPowerKw, 0, 0)
    if power < config.MIN_POWER_KW or power > config.MAX_POWER_KW then
        return false
    end

    if power >= config.MID_POWER_MIN_KW and power < config.MID_POWER_MAX_KW then
        return resolvedYear >= config.MID_POWER_YEAR
    end

    return resolvedYear >= config.OUTER_POWER_YEAR
end

function RMS_Exhaust.calculateWetStackingLevel(input)
    local currentLevel = getNumber(input.currentLevel, 0, 0, 1)
    if input.isDiesel ~= true then
        return 0
    end
    if input.isMotorStarted ~= true then
        return currentLevel
    end

    local fuelConfig = RMS_Config.CORE.FUEL_FACTOR_DATA
    local idleTimer = getNumber(input.idleTimer, 0, 0, fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER)
    local load = getNumber(input.load, 0, 0, 1.5)
    local dt = getNumber(input.dt, 100, 1)
    local coldTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
    local operatingTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP
    local engineTemperature = getNumber(input.engineTemperature, operatingTemperature, -80, 160)

    if input.isIdle == true then
        if idleTimer < fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD then
            return currentLevel
        end

        local coldRisk = 1 - getRamp(engineTemperature, coldTemperature, operatingTemperature)
        local coldMultiplier = 1 + coldRisk
        local idleStep = dt / 1000
        local threshold = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD
        local buildupDuration = math.max(fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - threshold, 1)
        local previousIdleTimer = math.max(idleTimer - idleStep, 0)
        local buildupStart = math.max(previousIdleTimer, threshold)
        local buildupSeconds = math.max(idleTimer - buildupStart, 0)
        local buildup = (buildupSeconds / buildupDuration) * coldMultiplier

        return clamp(currentLevel + buildup, 0, 1)
    end

    local loadFactor = getRamp(load, fuelConfig.IDLE_DEPOSIT_LOAD_THRESHOLD, 1)
    local temperatureFactor = getRamp(engineTemperature, coldTemperature, operatingTemperature)
    local cleanupDuration = math.max(
        fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD,
        1
    )
    local cleanup = (dt / 1000) / cleanupDuration * loadFactor * temperatureFactor

    return clamp(currentLevel - cleanup, 0, 1)
end

function RMS_Exhaust.calculateTargets(input)
    local config = RMS_Config.EXHAUST
    local sootConfig = config.SOOT
    local oilConfig = config.OIL
    local unburntConfig = config.UNBURNT
    local load = getNumber(input.load, 0, 0, 1.5)
    local lastLoad = getNumber(input.lastLoad, load, 0, 1.5)
    local dt = getNumber(input.dt, 100, 1)
    local eraFactor = RMS_Exhaust.getEraFactor(input.year)
    local isStageV = RMS_Exhaust.getIsStageV(input.year, input.peakPowerKw)
    local wetStackingLevel = getNumber(input.wetStackingLevel, 0, 0, 1)

    local sootContinuous = getRamp(load, sootConfig.LOAD_THRESHOLD, sootConfig.LOAD_FULL) * sootConfig.LOAD_MAX
    sootContinuous = sootContinuous + wetStackingLevel * sootConfig.WET_STACKING_MAX
    local loadRate = (load - lastLoad) / math.max(dt / 1000, 0.001)
    sootContinuous = sootContinuous + clamp(loadRate / sootConfig.TRANSIENT_LOAD_RATE, 0, 1) * sootConfig.TRANSIENT_MAX

    local clogging = getNumber(input.airIntakeClogging, 0, 0, 1)
    local cloggingCurve = clogging * clogging
    if clogging > sootConfig.AIR_INTAKE_KNEE then
        cloggingCurve = cloggingCurve + (clogging - sootConfig.AIR_INTAKE_KNEE)
    end
    sootContinuous = sootContinuous + math.min(cloggingCurve, 1) * sootConfig.AIR_INTAKE_MAX

    local serviceLoss = 1 - getNumber(input.serviceLevel, 1, 0, 1)
    sootContinuous = sootContinuous + getRamp(serviceLoss, sootConfig.SERVICE_THRESHOLD, 1) * sootConfig.SERVICE_MAX

    local breakdownFactor = math.max(eraFactor, config.ERA_BREAKDOWN_FLOOR)
    local sootBreakdown = getNumber(input.sootEffect, 0, 0, 1) * sootConfig.BREAKDOWN_MAX
    local sootProfileFactor = input.isMethane == true and config.METHANE_SOOT_FACTOR or 1
    if isStageV then
        sootProfileFactor = sootProfileFactor * config.STAGE_V.SOOT_FACTOR
    end
    local soot = clamp((sootContinuous * eraFactor + sootBreakdown * breakdownFactor) * sootProfileFactor, 0, 1)

    local oilBreakdown = getNumber(input.oilEffect, 0, 0, 1) * oilConfig.BREAKDOWN_MAX
    if load <= oilConfig.IDLE_LOAD_THRESHOLD then
        oilBreakdown = oilBreakdown * oilConfig.IDLE_BOOST
    end
    local oil = clamp(oilBreakdown * breakdownFactor, 0, 1)

    local engineTemperature = getNumber(input.engineTemperature, unburntConfig.COLD_THRESHOLD_C, -80, 160)
    local cold = 1 - getRamp(engineTemperature, unburntConfig.COLD_FULL_C, unburntConfig.COLD_THRESHOLD_C)
    local unburntContinuous = cold * unburntConfig.COLD_MAX
    if input.isStarting == true then
        unburntContinuous = unburntContinuous * unburntConfig.CRANKING_BOOST
    end
    local preheatSeverity = getNumber(input.preheatSeverity, 0, 0, 4)
    unburntContinuous = unburntContinuous + (preheatSeverity / 4) * cold * unburntConfig.PREHEAT_FAULT_MAX
    local unburntBreakdown = getNumber(input.unburntEffect, 0, 0, 1) * unburntConfig.BREAKDOWN_MAX
    local unburnt = clamp(unburntContinuous * eraFactor + unburntBreakdown * breakdownFactor, 0, 1)

    local healthyAlphaFactor = eraFactor
    if input.hasDEF == true then
        healthyAlphaFactor = healthyAlphaFactor * config.DEF_HEALTHY_ALPHA_FACTOR
    end
    if input.isMethane == true then
        healthyAlphaFactor = healthyAlphaFactor * config.METHANE_HEALTHY_ALPHA_FACTOR
    end
    if isStageV then
        healthyAlphaFactor = healthyAlphaFactor * config.STAGE_V.HEALTHY_ALPHA_FACTOR
    end

    return {
        eraFactor = eraFactor,
        isStageV = isStageV,
        healthyAlphaFactor = healthyAlphaFactor,
        loadDensityFactor = lerp(config.LOAD_DENSITY_IDLE_FACTOR, 1, clamp(load, 0, 1)),
        soot = soot,
        oil = oil,
        unburnt = unburnt
    }
end

local function getEffectIntensity(spec, effectId)
    local effect = spec.activeEffects ~= nil and spec.activeEffects[effectId] or nil
    return clamp(effect ~= nil and getNumber(effect.value, 0) or 0, 0, 1)
end

local function getSmoothed(current, target, dt)
    local tau = target > current and RMS_Config.EXHAUST.RISE_TAU or RMS_Config.EXHAUST.FALL_TAU
    local alpha = math.min(dt / (tau + dt), 1)

    return current + alpha * (target - current)
end

local function getRpmScale(vehicle)
    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    if motor == nil then
        return 0
    end

    local maxRpm = motor:getMaxRpm()
    if maxRpm == nil or maxRpm <= 0 then
        return 0
    end

    return (vehicle:getMotorRpmReal() or 0) / maxRpm
end

local function getIsSmokeRendered(vehicle)
    local motorState = vehicle.getMotorState ~= nil and vehicle:getMotorState() or MotorState.OFF

    return motorState == MotorState.STARTING or motorState == MotorState.ON
end

local function resolveEmissionProfile(vehicle, state)
    if state.profileResolved then
        return
    end

    local motorizedSpec = vehicle.spec_motorized
    local consumers = motorizedSpec ~= nil and motorizedSpec.consumersByFillTypeName or nil
    if consumers == nil then
        return
    end

    state.hasDEF = consumers["DEF"] ~= nil
    state.isMethane = consumers["METHANE"] ~= nil
    state.profileResolved = true
end

local function getPeakPowerKw(vehicle)
    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    return motor ~= nil and getNumber(motor.peakMotorPower, 0, 0) or 0
end

local function restoreEffects(effects)
    for _, effect in pairs(effects) do
        if effect.rmsBaseMinRpmColor ~= nil then
            effect.minRpmColor = effect.rmsBaseMinRpmColor
            effect.maxRpmColor = effect.rmsBaseMaxRpmColor
            effect.rmsBaseMinRpmColor = nil
            effect.rmsBaseMaxRpmColor = nil
        end
    end
end

local function writeEffects(effects, state)
    for _, effect in pairs(effects) do
        if effect.rmsBaseMinRpmColor == nil then
            effect.rmsBaseMinRpmColor = effect.minRpmColor
            effect.rmsBaseMaxRpmColor = effect.maxRpmColor
            effect.minRpmColor = {}
            effect.maxRpmColor = {}
        end

        effect.minRpmColor[1] = state.red
        effect.minRpmColor[2] = state.green
        effect.minRpmColor[3] = state.blue
        effect.minRpmColor[4] = state.alphaIdle
        effect.maxRpmColor[1] = state.red
        effect.maxRpmColor[2] = state.green
        effect.maxRpmColor[3] = state.blue
        effect.maxRpmColor[4] = state.alphaFull
    end
end

local function resetState(state)
    local config = RMS_Config.EXHAUST

    state.soot = 0
    state.oil = 0
    state.unburnt = 0
    state.eraFactor = 1
    state.isStageV = false
    state.red = config.HEALTHY_TINT[1]
    state.green = config.HEALTHY_TINT[2]
    state.blue = config.HEALTHY_TINT[3]
    state.alphaIdle = config.HEALTHY_ALPHA_IDLE
    state.alphaFull = config.HEALTHY_ALPHA_FULL
    state.lastLoad = 0
    state.isActive = false
end

function RMS_Exhaust.initSpec(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    local state = {
        profileResolved = false,
        hasDEF = false,
        isMethane = false
    }
    spec.exhaustSmoke = state
    resetState(state)
end

function RMS_Exhaust.reset(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local state = spec ~= nil and spec.exhaustSmoke or nil
    if state == nil then
        return
    end

    local motorizedSpec = vehicle.spec_motorized
    local effects = motorizedSpec ~= nil and motorizedSpec.exhaustEffects or nil
    if state.isActive and effects ~= nil then
        restoreEffects(effects)
    end

    resetState(state)
end

function RMS_Exhaust.update(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.exhaustSmoke
    local motorizedSpec = vehicle.spec_motorized
    local effects = motorizedSpec ~= nil and motorizedSpec.exhaustEffects or nil

    if effects == nil or next(effects) == nil then
        return
    end

    local config = RMS_Config.EXHAUST
    if not config.ENABLED or not getIsSmokeRendered(vehicle) then
        RMS_Exhaust.reset(vehicle)
        return
    end

    resolveEmissionProfile(vehicle, state)

    local load = getNumber(spec.dynamicMotorLoad, 0, 0, 1.5)
    local motorState = vehicle.getMotorState ~= nil and vehicle:getMotorState() or MotorState.OFF
    local targets = RMS_Exhaust.calculateTargets({
        year = spec.year,
        peakPowerKw = getPeakPowerKw(vehicle),
        hasDEF = state.hasDEF,
        isMethane = state.isMethane,
        load = load,
        lastLoad = state.lastLoad,
        dt = dt,
        airIntakeClogging = spec.airIntakeClogging,
        serviceLevel = spec.serviceLevel,
        engineTemperature = spec.rawEngineTemperature or spec.engineTemperature,
        isStarting = motorState == MotorState.STARTING,
        preheatSeverity = spec.preheatColdStartFaultSeverity,
        wetStackingLevel = spec.fuelState ~= nil and spec.fuelState.wetStackingLevel or 0,
        sootEffect = getEffectIntensity(spec, "EXHAUST_SOOT"),
        oilEffect = getEffectIntensity(spec, "EXHAUST_OIL"),
        unburntEffect = getEffectIntensity(spec, "EXHAUST_UNBURNT")
    })
    state.lastLoad = load
    state.eraFactor = targets.eraFactor
    state.isStageV = targets.isStageV
    state.soot = getSmoothed(state.soot, targets.soot, dt)
    state.oil = getSmoothed(state.oil, targets.oil, dt)
    state.unburnt = getSmoothed(state.unburnt, targets.unburnt, dt)

    local total = state.soot + state.oil + state.unburnt
    local saturation = math.min(total, 1)
    local healthyWeight = (1 - saturation) ^ config.TINT_CONCENTRATION
    local weightSum = total + healthyWeight

    local sootTint = config.SOOT_TINT
    local oilTint = config.OIL_TINT
    local unburntTint = config.UNBURNT_TINT
    local healthyTint = config.HEALTHY_TINT
    state.red = (state.soot * sootTint[1] + state.oil * oilTint[1] + state.unburnt * unburntTint[1] + healthyWeight * healthyTint[1]) / weightSum
    state.green = (state.soot * sootTint[2] + state.oil * oilTint[2] + state.unburnt * unburntTint[2] + healthyWeight * healthyTint[2]) / weightSum
    state.blue = (state.soot * sootTint[3] + state.oil * oilTint[3] + state.unburnt * unburntTint[3] + healthyWeight * healthyTint[3]) / weightSum

    local visibleSaturation = saturation * targets.loadDensityFactor
    local intensity = clamp(getNumber(config.INTENSITY, 1), 1, 3)
    local healthyAlphaIdle = config.HEALTHY_ALPHA_IDLE * targets.healthyAlphaFactor
    local healthyAlphaFull = config.HEALTHY_ALPHA_FULL * targets.healthyAlphaFactor
    state.alphaIdle = lerp(healthyAlphaIdle, config.SATURATED_ALPHA_IDLE, visibleSaturation) * intensity
    state.alphaFull = lerp(healthyAlphaFull, config.SATURATED_ALPHA_FULL, visibleSaturation) * intensity

    state.isActive = true
    writeEffects(effects, state)
end

function RMS_Exhaust.applyShader(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.exhaustSmoke
    if not state.isActive or not getIsSmokeRendered(vehicle) then
        return
    end

    local effects = vehicle.spec_motorized.exhaustEffects
    local rpmScale = getRpmScale(vehicle)
    local alpha = lerp(state.alphaIdle, state.alphaFull, rpmScale)

    for _, effect in pairs(effects) do
        local scale = lerp(effect.minRpmScale, effect.maxRpmScale, rpmScale)

        setShaderParameter(effect.effectNode, "exhaustColor", state.red, state.green, state.blue, alpha, false)
        setShaderParameter(effect.effectNode, "param", effect.xRot, effect.zRot, 0, scale, false)
    end
end
