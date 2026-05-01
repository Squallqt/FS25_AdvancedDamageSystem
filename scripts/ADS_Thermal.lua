

ADS_Thermal = ADS_Thermal or {}

-- ==========================================================
--                     HELPERS
-- ==========================================================

local function hasCVTTransmission(vehicle)
    local motor = vehicle:getMotor()
    return motor ~= nil and motor.minForwardGearRatio ~= nil
end

local function hasCVTAddon(vehicle)
    local spec_CVTaddon = vehicle.spec_CVTaddon
    local cvtAddonConfig = spec_CVTaddon ~= nil and (tonumber(spec_CVTaddon.CVTconfig) or 0) or 0
    local hasActiveCVTAddon = spec_CVTaddon ~= nil
        and spec_CVTaddon.CVTcfgExists
        and cvtAddonConfig ~= 0
        and cvtAddonConfig ~= 8
    return hasActiveCVTAddon
end

local function getSpeedCooling(vehicle)
    local C = ADS_Config.THERMAL
    local speed = vehicle:getLastSpeed()
    if speed > C.SPEED_COOLING_MIN_SPEED then
        local speedRatio = math.min((speed - C.SPEED_COOLING_MIN_SPEED) / (C.SPEED_COOLING_MAX_SPEED - C.SPEED_COOLING_MIN_SPEED), 1.0)
        return C.SPEED_COOLING_MAX_EFFECT * speedRatio
    end
    return 0
end

-- ==========================================================
--                     MAIN
-- ==========================================================

function ADS_Thermal:updateThermalSystems(dt)
    local motor = self:getMotor()
    if not motor then return end

    local spec = self.spec_AdvancedDamageSystem
    local vehicleHaveCVT = hasCVTTransmission(self)

    local isMotorStarted = self:getIsMotorStarted()
    local motorLoad = spec.dynamicMotorLoad or math.max(self:getMotorLoadPercentage(), 0.0)
    local motorRpm = self:getMotorRpmPercentage()
    local dirt = spec.radiatorClogging
    local eviromentTemp = g_currentMission.environment.weather.forecast:getCurrentWeather().temperature

    if (spec.engineTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.engineTemperature = eviromentTemp end
    if (spec.rawEngineTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.rawEngineTemperature = eviromentTemp end
    if vehicleHaveCVT then
        if (spec.transmissionTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.transmissionTemperature = eviromentTemp end
        if (spec.rawTransmissionTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.rawTransmissionTemperature = eviromentTemp end
    end

    if not spec.isElectricVehicle then
        self:updateEngineThermalModel(dt, spec, isMotorStarted, motorLoad, eviromentTemp, dirt)
    end

    if vehicleHaveCVT then
        if hasCVTAddon(self) then
            spec.rawTransmissionTemperature = self.spec_motorized.motorTemperature.value
        else
            self:updateTransmissionThermalModel(dt, spec, isMotorStarted, motorLoad, motorRpm, eviromentTemp, dirt)
        end
    else
        spec.rawTransmissionTemperature = -99
    end
end

function ADS_Thermal:getSmoothedTemperature(dt)
    local C = ADS_Config.THERMAL
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then
        return
    end

    local alpha = dt / (C.TAU + dt)
    local eviromentTemp = g_currentMission.environment.weather.forecast:getCurrentWeather().temperature or 0
    local vehicleHaveCVT = hasCVTTransmission(self)
    local snapThreshold = 5.0

    local rawEngineTemperature = spec.rawEngineTemperature or eviromentTemp
    local currentEngineTemperature = spec.engineTemperature or rawEngineTemperature
    if math.abs(rawEngineTemperature - currentEngineTemperature) >= snapThreshold then
        spec.engineTemperature = math.max(rawEngineTemperature, eviromentTemp)
    else
        spec.engineTemperature = math.max(currentEngineTemperature + alpha * (rawEngineTemperature - currentEngineTemperature), eviromentTemp)
    end

    if vehicleHaveCVT then
        local rawTransmissionTemperature = spec.rawTransmissionTemperature or eviromentTemp
        local currentTransmissionTemperature = spec.transmissionTemperature or rawTransmissionTemperature
        if math.abs(rawTransmissionTemperature - currentTransmissionTemperature) >= snapThreshold then
            spec.transmissionTemperature = math.max(rawTransmissionTemperature, eviromentTemp)
        else
            spec.transmissionTemperature = math.max(currentTransmissionTemperature + alpha * (rawTransmissionTemperature - currentTransmissionTemperature), eviromentTemp)
        end
    end
end


-- ==========================================================
--                     ENGINE
-- ==========================================================

local function getEngineHeat(vehicle, spec, motorLoad, isMotorStarted)
    local C = ADS_Config.THERMAL
    if isMotorStarted == false then
        return 0
    end

    local engineMaxHeat = C.ENGINE_MAX_HEAT + spec.extraEngineHeat
    local warmBoost = spec.rawEngineTemperature < ADS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD and C.WARMING_BOOST_POWER or 1.0
    local heat = (C.ENGINE_MIN_HEAT + math.clamp(motorLoad, 0.1, 1.0) * (engineMaxHeat - C.ENGINE_MIN_HEAT)) * warmBoost
    return heat
end

local function getEngineCooling(vehicle, spec, eviromentTemp, dirt, isMotorStarted)
    local C = ADS_Config.THERMAL
    local deltaTemp = math.max(0, spec.rawEngineTemperature - eviromentTemp)
    local convectionCooling = C.CONVECTION_FACTOR * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    local speedCooling = getSpeedCooling(vehicle)

    if isMotorStarted == false then
        if (spec.engineTemperature or -99) < C.PID_TARGET_TEMP then
            return convectionCooling / C.COOLING_SLOWDOWN_POWER, 0, convectionCooling, speedCooling
        else
            return convectionCooling, 0, convectionCooling, speedCooling
        end
    end

    local brokenFanModifier = 1.0
    if spec.fanClutchHealth < 1.0 then
        local speed = vehicle:getLastSpeed()
        if speed < C.SPEED_COOLING_MIN_SPEED then
            local speedK = 1 - speed / C.SPEED_COOLING_MIN_SPEED
            brokenFanModifier = 1 - math.min(speedK * (1 - spec.fanClutchHealth), 0.5)
        end
    end

    local dirtRadiatorMaxCooling = (C.ENGINE_RADIATOR_MAX_COOLING * spec.radiatorHealth) * (1 - C.MAX_DIRT_INFLUENCE * (dirt ^ 3)) * brokenFanModifier
    local radiatorCooling = math.max(dirtRadiatorMaxCooling * spec.thermostatState, C.ENGINE_RADIATOR_MIN_COOLING) * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    return (radiatorCooling + convectionCooling) * (1 + speedCooling), radiatorCooling, convectionCooling, speedCooling
end

function ADS_Thermal:updateEngineThermalModel(dt, spec, isMotorStarted, motorLoad, eviromentTemp, dirt)
    local C = ADS_Config.THERMAL
    local heat, cooling = 0, 0
    local radiatorCooling, convectionCooling = 0, 0
    local speedCooling = 0

    heat = getEngineHeat(self, spec, motorLoad, isMotorStarted)
    cooling, radiatorCooling, convectionCooling, speedCooling = getEngineCooling(self, spec, eviromentTemp, dirt, isMotorStarted)

    spec.rawEngineTemperature = spec.rawEngineTemperature + (heat - cooling) * (dt / 1000) * C.TEMPERATURE_CHANGE_SPEED
    spec.rawEngineTemperature = math.max(spec.rawEngineTemperature, eviromentTemp)

    local dbg = spec.debugData.engineTemp

    local rawEngineTemp = spec.rawEngineTemperature or spec.engineTemperature or -99
    if isMotorStarted and rawEngineTemp > C.ENGINE_THERMOSTAT_MIN_TEMP then
        spec.thermostatState = ADS_Thermal.getNewTermostatState(dt, rawEngineTemp, C.PID_TARGET_TEMP, spec.engTermPID, spec.thermostatHealth, spec.year, spec.thermostatStuckedPosition, dbg)
    else
        spec.thermostatState = 0.0
        spec.engTermPID.integral = 0
        spec.engTermPID.lastError = 0

        dbg.kp = 0
        dbg.stiction = 0
        dbg.waxSpeed = 0
    end

    dbg.totalHeat = heat
    dbg.totalCooling = cooling
    dbg.radiatorCooling = radiatorCooling
    dbg.speedCooling = speedCooling
    dbg.convectionCooling = convectionCooling

    return dbg
end

-- ==========================================================
--                     TRANSMISSION
-- ==========================================================

local function getTransmissionHeat(vehicle, spec, isMotorStarted, motorLoad, motorRpm)
    local C = ADS_Config.THERMAL
    local motor = vehicle:getMotor()

    local loadFactor = math.clamp(motorLoad - motor.motorExternalTorque / motor.peakMotorTorque, C.TRANS_MIN_HEAT, 1.1)
    local slipFactor = 1.0
    local wheelSlipFactor = 1.0
    local accFactor = 1.0
    local cvtSlipActive = false
    local cvtSlipLocked = false

    if isMotorStarted == false then
        return 0, loadFactor, slipFactor, wheelSlipFactor, accFactor, cvtSlipActive, cvtSlipLocked
    end

    local accelerationAxis = vehicle.getAccelerationAxis ~= nil and (tonumber(vehicle:getAccelerationAxis()) or 0) or 0
    local cruiseControlAxis = vehicle.getCruiseControlAxis ~= nil and (tonumber(vehicle:getCruiseControlAxis()) or 0) or 0

    if accelerationAxis > 0 or cruiseControlAxis > 0 then
        accFactor = math.clamp(5 * motorRpm * math.clamp(motor.motorRotAccelerationSmoothed / motor.motorRotationAccelerationLimit, 0.0, 1.0), 1.0, 2.0)
    end

    -- slip effect from breakdown
    if spec.activeEffects.CVT_SLIP_EFFECT ~= nil and spec.activeEffects.CVT_SLIP_EFFECT.value > 0 then
        cvtSlipActive = true
        local curSpeed = math.min(motor.vehicle:getLastSpeed() / (motor:getMaximumForwardSpeed() * 3.6), 1.0)
        local minGearRatio, maxGearRatio = motor:getMinMaxGearRatio()
        local isSliping = (1 - minGearRatio / math.max(motor.gearRatio, 0.01) <= 0.02) and curSpeed < 0.8
        if isSliping then
            cvtSlipLocked = true
            slipFactor = slipFactor * 2.0
        end
    end

    -- wheel slip
    if spec.wheelSlipIntensity ~= nil and spec.wheelSlipIntensity > 0.05 then
        wheelSlipFactor = math.min(wheelSlipFactor + ((spec.wheelSlipIntensity or 0) / 2) * (spec.avgTireGroundFrictionCoeff ^ 2), 1.4)
    end

    local maxHeat = C.TRANS_MAX_HEAT + spec.extraTransmissionHeat
    local warmBoost = spec.rawTransmissionTemperature < ADS_Config.CORE.TRANSMISSION_FACTOR_DATA.COLD_TRANSMISSION_THRESHOLD and C.WARMING_BOOST_POWER or 1.0
    local heat = C.TRANS_MIN_HEAT + (maxHeat - C.TRANS_MIN_HEAT) * loadFactor * slipFactor * accFactor * wheelSlipFactor * warmBoost

    return heat, loadFactor, slipFactor, wheelSlipFactor, accFactor, cvtSlipActive, cvtSlipLocked
end

local function getTransmissionCooling(vehicle, spec, eviromentTemp, dirt, isMotorStarted)
    local C = ADS_Config.THERMAL
    local deltaTemp = math.max(0, spec.rawTransmissionTemperature - eviromentTemp)
    local convectionCooling = C.CONVECTION_FACTOR * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    local speedCooling = getSpeedCooling(vehicle)

    if isMotorStarted == false then
        if (spec.rawTransmissionTemperature or -99) < C.TRANS_PID_TARGET_TEMP then
            return convectionCooling / C.COOLING_SLOWDOWN_POWER, 0, convectionCooling, speedCooling
        else
            return convectionCooling, 0, convectionCooling, speedCooling
        end
    end

    local dirtRadiatorMaxCooling = C.TRANS_RADIATOR_MAX_COOLING * (1 - C.MAX_DIRT_INFLUENCE * (dirt ^ 3))
    local radiatorCooling = math.max(dirtRadiatorMaxCooling * spec.transmissionThermostatState, C.TRANS_RADIATOR_MIN_COOLING) * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    return (radiatorCooling + convectionCooling) * (1 + speedCooling), radiatorCooling, convectionCooling, speedCooling
end

function ADS_Thermal:updateTransmissionThermalModel(dt, spec, isMotorStarted, motorLoad, motorRpm, eviromentTemp, dirt)
    local C = ADS_Config.THERMAL
    local heat, cooling = 0, 0
    local radiatorCooling, convectionCooling = 0, 0
    local speedCooling = 0
    local loadFactor = 0
    local slipFactor = 1.0
    local wheelSlipFactor = 1.0
    local accFactor = 1.0
    local cvtSlipActive = false
    local cvtSlipLocked = false

    local dbg = spec.debugData.transmissionTemp

    heat, loadFactor, slipFactor, wheelSlipFactor, accFactor, cvtSlipActive, cvtSlipLocked = getTransmissionHeat(self, spec, isMotorStarted, motorLoad, motorRpm)
    cooling, radiatorCooling, convectionCooling, speedCooling = getTransmissionCooling(self, spec, eviromentTemp, dirt, isMotorStarted)

    spec.rawTransmissionTemperature = spec.rawTransmissionTemperature + (heat - cooling) * (dt / 1000) * C.TEMPERATURE_CHANGE_SPEED
    spec.rawTransmissionTemperature = math.max(spec.rawTransmissionTemperature, eviromentTemp)

    local rawTransmissionTemp = spec.rawTransmissionTemperature or spec.transmissionTemperature or -99
    if isMotorStarted and rawTransmissionTemp > C.TRANS_THERMOSTAT_MIN_TEMP then
        spec.transmissionThermostatState = ADS_Thermal.getNewTermostatState(dt, rawTransmissionTemp, C.TRANS_PID_TARGET_TEMP, spec.transTermPID, spec.transmissionThermostatHealth, spec.year, spec.transmissionThermostatStuckedPosition, dbg)
    else
        spec.transmissionThermostatState = 0.0
        spec.transTermPID.integral = 0
        spec.transTermPID.lastError = 0

        if dbg then
            dbg.kp = 0
            dbg.stiction = 0
            dbg.waxSpeed = 0
        end
    end

    if dbg then
        dbg.totalHeat = heat
        dbg.totalCooling = cooling
        dbg.radiatorCooling = radiatorCooling
        dbg.speedCooling = speedCooling
        dbg.convectionCooling = convectionCooling
        dbg.loadFactor = loadFactor
        dbg.slipFactor = slipFactor
        dbg.wheelSlipFactor = wheelSlipFactor
        dbg.accFactor = accFactor
        dbg.cvtSlipActive = cvtSlipActive and 1 or 0
        dbg.cvtSlipLocked = cvtSlipLocked and 1 or 0
        dbg.extraTransmissionHeat = spec.extraTransmissionHeat or 0
    end

    return dbg
end

-- ==========================================================
--                     TERMOSTAT
-- ==========================================================

function ADS_Thermal.getNewTermostatState(dt, currentTemp, targetTemp, pidData, thermostatHealth, year, stuckedPosition, debugData)
    if stuckedPosition ~= nil then
        return stuckedPosition
    end

    local C = ADS_Config.THERMAL
    local dtSeconds = math.max(dt / 1000, 0.001)

    local isMechanical = year < C.THERMOSTAT_TYPE_YEAR_DIVIDER
    local targetPos = 0
    local maxOpening = 1.0

    if isMechanical then
        local startOpenTemp = targetTemp - 7
        local fullOpenTemp = targetTemp + 5
        targetPos = (currentTemp - startOpenTemp) / (fullOpenTemp - startOpenTemp)
        pidData.integral = 0
        pidData.lastError = 0
        if debugData then debugData.kp = 0 end
    else
        local pidKpYearFactor = (year - C.THERMOSTAT_TYPE_YEAR_DIVIDER) / (C.ELECTRONIC_THERMOSTAT_MAX_YEAR - C.THERMOSTAT_TYPE_YEAR_DIVIDER)
        local pid_kp = math.clamp(C.PID_KP_MIN + (C.PID_KP_MAX - C.PID_KP_MIN) * pidKpYearFactor, C.PID_KP_MIN, C.PID_KP_MAX)
        local errorTemp = currentTemp - targetTemp

        local derivative = 0
        if dtSeconds > 0.001 then
            derivative = (errorTemp - (pidData.lastError or 0)) / dtSeconds
        end

        local newIntegral = (pidData.integral or 0) + errorTemp * dtSeconds
        local controlSignal = pid_kp * errorTemp + C.PID_KI * newIntegral + C.PID_KD * derivative

        if (controlSignal >= 0 and controlSignal <= maxOpening) or
           (controlSignal < 0 and errorTemp > 0) or
           (controlSignal > maxOpening and errorTemp < 0) then

            pidData.integral = math.clamp(newIntegral, -C.PID_MAX_INTEGRAL, C.PID_MAX_INTEGRAL)
        end

        targetPos = pid_kp * errorTemp + C.PID_KI * pidData.integral + C.PID_KD * derivative
        pidData.lastError = errorTemp

        if debugData then debugData.kp = pid_kp end
    end

    targetPos = math.clamp(targetPos, 0.0, maxOpening)

    local baseSpeed = isMechanical and C.MECHANIC_THERMOSTAT_MIN_WAX_SPEED or C.ELECTRONIC_THERMOSTAT_MIN_WAX_SPEED
    local yearFactor = isMechanical and (year - 1950) * 0.0005 or (year - 2000) * 0.0016

    local waxSpeed = math.clamp(baseSpeed + yearFactor, C.MECHANIC_THERMOSTAT_MIN_WAX_SPEED, C.ELECTRONIC_THERMOSTAT_MAX_WAX_SPEED)
    waxSpeed = waxSpeed * math.max(0.2, thermostatHealth)

    local currentMechPos = pidData.mechPos or 0.0
    local delta = targetPos - currentMechPos
    local maxMove = waxSpeed * dtSeconds

    if math.abs(delta) > maxMove then
        delta = maxMove * (delta > 0 and 1 or -1)
    end

    local newPos = math.clamp(currentMechPos + delta, 0.0, maxOpening)
    pidData.mechPos = newPos

    local baseStiction = isMechanical and (0.1 - (year - 1950) * 0.0016) or (0.05 - (year - 2000) * 0.0016)
    local stiction = math.clamp(baseStiction, 0.01, 0.1)

    stiction = stiction * (2 - math.max(0.5, thermostatHealth))

    if debugData then
        debugData.stiction = stiction
        debugData.waxSpeed = waxSpeed
    end

    return math.clamp(math.floor(newPos / stiction) * stiction, 0.0, maxOpening)
end
