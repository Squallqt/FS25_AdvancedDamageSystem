-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Engine and transmission temperature model, with the engine and transmission thermostats
RMS_Thermal = RMS_Thermal or {}

local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber

---Returns the extra cooling brought by driving speed, none below the configured minimum speed
-- @param table vehicle vehicle
-- @return float cooling additional cooling ratio
local function getSpeedCooling(vehicle)
    local C = RMS_Config.THERMAL
    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
    if speed > C.SPEED_COOLING_MIN_SPEED then
        local speedRatio = math.min((speed - C.SPEED_COOLING_MIN_SPEED) / (C.SPEED_COOLING_MAX_SPEED - C.SPEED_COOLING_MIN_SPEED), 1.0)
        return C.SPEED_COOLING_MAX_EFFECT * speedRatio
    end
    return 0
end

---Runs the engine and transmission thermal models against the current weather temperature
-- @param float dt time since last call in ms
-- @param boolean updateEngine true to run the engine model
-- @param boolean updateTransmission true to run the transmission model
function RMS_Thermal:updateThermalSystems(dt, updateEngine, updateTransmission)
    local motor = self:getMotor()
    if not motor then return end

    local spec = self.spec_RealisticMechanicalSystems
    local isMotorStarted = self:getIsMotorStarted()
    local motorLoad = sanitizeNumber(spec.dynamicMotorLoad or self:getMotorLoadPercentage(), 0, 0, 1.5)
    local motorRpm = sanitizeNumber(self:getMotorRpmPercentage(), 0, 0, 1.5)
    local dirt = sanitizeNumber(spec.radiatorClogging, 0, 0, 1)
    local eviromentTemp = 20
    if g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.weather ~= nil and g_currentMission.environment.weather.forecast ~= nil then
        local weather = g_currentMission.environment.weather.forecast:getCurrentWeather()
        eviromentTemp = sanitizeNumber(weather ~= nil and weather.temperature or nil, 20, -80, 80)
    end

    spec.engineTemperature = sanitizeNumber(spec.engineTemperature, eviromentTemp, -80, 160)
    spec.rawEngineTemperature = sanitizeNumber(spec.rawEngineTemperature, eviromentTemp, -80, 160)
    spec.transmissionTemperature = sanitizeNumber(spec.transmissionTemperature, eviromentTemp, -80, 180)
    spec.rawTransmissionTemperature = sanitizeNumber(spec.rawTransmissionTemperature, eviromentTemp, -80, 180)
    spec.thermostatState = sanitizeNumber(spec.thermostatState, 0, 0, 1)
    spec.transmissionThermostatState = sanitizeNumber(spec.transmissionThermostatState, 0, 0, 1)

    -- temperatures never fall below ambient, and reset to it while sleeping with the motor off
    if (spec.engineTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.engineTemperature = eviromentTemp end
    if (spec.rawEngineTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.rawEngineTemperature = eviromentTemp end
    if (spec.transmissionTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.transmissionTemperature = eviromentTemp end
    if (spec.rawTransmissionTemperature or -99) < eviromentTemp or (g_sleepManager.isSleeping and not isMotorStarted) then spec.rawTransmissionTemperature = eviromentTemp end

    if updateEngine and not spec.isElectricVehicle then
        self:updateEngineThermalModel(dt, spec, isMotorStarted, motorLoad, eviromentTemp, dirt)
    end

    if updateTransmission then
        self:updateTransmissionThermalModel(dt, spec, isMotorStarted, motorLoad, motorRpm, eviromentTemp, dirt)
    end
end

---Eases the displayed temperatures toward the raw ones, snapping past a five degree gap
-- @param float dt time since last call in ms
function RMS_Thermal:getSmoothedTemperature(dt)
    local C = RMS_Config.THERMAL
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local safeDt = sanitizeNumber(dt, 0, 0)
    local alpha = safeDt / (C.TAU + safeDt)
    local eviromentTemp = 20
    if g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.weather ~= nil and g_currentMission.environment.weather.forecast ~= nil then
        local weather = g_currentMission.environment.weather.forecast:getCurrentWeather()
        eviromentTemp = sanitizeNumber(weather ~= nil and weather.temperature or nil, 20, -80, 80)
    end
    local snapThreshold = 5.0

    local rawEngineTemperature = sanitizeNumber(spec.rawEngineTemperature, eviromentTemp, -80, 160)
    local currentEngineTemperature = sanitizeNumber(spec.engineTemperature, rawEngineTemperature, -80, 160)
    if math.abs(rawEngineTemperature - currentEngineTemperature) >= snapThreshold then
        spec.engineTemperature = math.max(rawEngineTemperature, eviromentTemp)
    else
        spec.engineTemperature = math.max(currentEngineTemperature + alpha * (rawEngineTemperature - currentEngineTemperature), eviromentTemp)
    end

    local rawTransmissionTemperature = sanitizeNumber(spec.rawTransmissionTemperature, eviromentTemp, -80, 180)
    local currentTransmissionTemperature = sanitizeNumber(spec.transmissionTemperature, rawTransmissionTemperature, -80, 180)
    if math.abs(rawTransmissionTemperature - currentTransmissionTemperature) >= snapThreshold then
        spec.transmissionTemperature = math.max(rawTransmissionTemperature, eviromentTemp)
    else
        spec.transmissionTemperature = math.max(currentTransmissionTemperature + alpha * (rawTransmissionTemperature - currentTransmissionTemperature), eviromentTemp)
    end
end

---Returns the engine heat output, scaled by motor load
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param float motorLoad motor load ratio
-- @param boolean isMotorStarted true while the motor runs
-- @return float heat heat output
local function getEngineHeat(vehicle, spec, motorLoad, isMotorStarted)
    local C = RMS_Config.THERMAL
    if isMotorStarted == false then
        return 0
    end

    local engineMaxHeat = C.ENGINE_MAX_HEAT + sanitizeNumber(spec.extraEngineHeat, 0, -C.ENGINE_MAX_HEAT, 1000)
    return C.ENGINE_MIN_HEAT + math.clamp(motorLoad, 0.1, 1.0) * (engineMaxHeat - C.ENGINE_MIN_HEAT)
end

---Returns the engine cooling from convection, the radiator and driving speed
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param float eviromentTemp ambient temperature
-- @param float dirt radiator clogging ratio
-- @param boolean isMotorStarted true while the motor runs
-- @return float cooling total cooling
-- @return float radiatorCooling radiator share
-- @return float convectionCooling convection share
-- @return float speedCooling speed share
local function getEngineCooling(vehicle, spec, eviromentTemp, dirt, isMotorStarted)
    local C = RMS_Config.THERMAL
    local rawEngineTemperature = sanitizeNumber(spec.rawEngineTemperature, eviromentTemp, -80, 160)
    local deltaTemp = math.max(0, rawEngineTemperature - eviromentTemp)
    local convectionCooling = C.CONVECTION_FACTOR * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    local speedCooling = getSpeedCooling(vehicle)

    if isMotorStarted == false then
        if (spec.engineTemperature or -99) < C.PID_TARGET_TEMP then
            return convectionCooling / C.COOLING_SLOWDOWN_POWER, 0, convectionCooling, speedCooling
        else
            return convectionCooling, 0, convectionCooling, speedCooling
        end
    end

    -- a worn fan clutch only costs cooling below the speed at which airflow takes over
    local brokenFanModifier = 1.0
    local fanClutchHealth = sanitizeNumber(spec.fanClutchHealth, 1.0, 0, 1)
    if fanClutchHealth < 1.0 then
        local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
        if speed < C.SPEED_COOLING_MIN_SPEED then
            local speedK = 1 - speed / C.SPEED_COOLING_MIN_SPEED
            brokenFanModifier = 1 - math.min(speedK * (1 - fanClutchHealth), 0.5)
        end
    end

    local radiatorHealth = sanitizeNumber(spec.radiatorHealth, 1.0, 0, 1)
    local thermostatState = sanitizeNumber(spec.thermostatState, 0, 0, 1)
    local coolantFactor = RMS_Utils.getFluidCapacityFactor(spec.coolantLevel, RMS_Config.FLUIDS.MIN_COOLING_FACTOR)
    local dirtRadiatorMaxCooling = (C.ENGINE_RADIATOR_MAX_COOLING * radiatorHealth * coolantFactor) * (1 - C.MAX_DIRT_INFLUENCE * (dirt ^ 2)) * brokenFanModifier
    local radiatorCooling = math.max(dirtRadiatorMaxCooling * thermostatState, C.ENGINE_RADIATOR_MIN_COOLING) * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    return (radiatorCooling + convectionCooling) * (1 + speedCooling), radiatorCooling, convectionCooling, speedCooling
end

---Advances the raw engine temperature by heat minus cooling, then updates its thermostat
-- @param float dt time since last call in ms
-- @param table spec vehicle spec
-- @param boolean isMotorStarted true while the motor runs
-- @param float motorLoad motor load ratio
-- @param float eviromentTemp ambient temperature
-- @param float dirt radiator clogging ratio
-- @return table dbg engine temperature debug data
function RMS_Thermal:updateEngineThermalModel(dt, spec, isMotorStarted, motorLoad, eviromentTemp, dirt)
    local C = RMS_Config.THERMAL
    local heat, cooling = 0, 0
    local radiatorCooling, convectionCooling = 0, 0
    local speedCooling = 0

    heat = getEngineHeat(self, spec, motorLoad, isMotorStarted)
    cooling, radiatorCooling, convectionCooling, speedCooling = getEngineCooling(self, spec, eviromentTemp, dirt, isMotorStarted)

    local safeDt = sanitizeNumber(dt, 0, 0)
    spec.rawEngineTemperature = sanitizeNumber(spec.rawEngineTemperature + (heat - cooling) * (safeDt / 1000) * C.ENGINE_TEMPERATURE_CHANGE_SPEED * C.TEMPERATURE_CHANGE_SPEED, eviromentTemp, -80, 160)
    spec.rawEngineTemperature = math.max(spec.rawEngineTemperature, eviromentTemp)

    local dbg = spec.debugData.engineTemp

    local rawEngineTemp = sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, eviromentTemp, -80, 160)
    if isMotorStarted and rawEngineTemp > C.ENGINE_THERMOSTAT_MIN_TEMP then
        spec.thermostatState = RMS_Thermal.getNewTermostatState(dt, rawEngineTemp, C.PID_TARGET_TEMP, spec.engTermPID, spec.thermostatHealth, spec.year, spec.thermostatStuckedPosition, dbg)
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

---Returns the transmission heat from oil circulation, the pump, the pto, load, the hydrostatic ratio, wheel slip and hydraulic work
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param boolean isMotorStarted true while the motor runs
-- @param float motorLoad motor load ratio
-- @param float motorRpm motor rpm ratio
-- @return float heat heat output
-- @return float loadFactor share of the motor load that passes through the gearbox
-- @return float hydrostaticFactor hydrostatic contribution
-- @return float wheelSlipFactor wheel slip contribution
-- @return float accFactor acceleration contribution
-- @return boolean cvtSlipActive true when the cvt slip effect is present
-- @return boolean cvtSlipLocked true when the cvt slip effect is actually slipping
-- @return float idleHeat circulation and pump contribution
-- @return float ptoHeat pto contribution
-- @return float hydraulicHeat hydraulic contribution
local function getTransmissionHeat(vehicle, spec, isMotorStarted, motorLoad, motorRpm)
    local C = RMS_Config.THERMAL
    local motor = vehicle:getMotor()

    -- load and rpm terms, against the torque available at the current rpm
    local availableTorque = sanitizeNumber(motor:getMotorAvailableTorque(), 0, 0, 1000000)
    local externalTorque = sanitizeNumber(motor:getMotorExternalTorque(), 0, 0, 1000000)
    local ptoShare = availableTorque > 0.001 and math.clamp(externalTorque / availableTorque, 0.0, 1.0) or 0
    local loadFactor = math.clamp(motorLoad - ptoShare, 0.0, 1.1)
    local hydrostaticFactor = 1.0
    local wheelSlipFactor = 1.0
    local accFactor = 1.0
    local cvtSlipActive = false
    local cvtSlipLocked = false
    local idleHeat = 0
    local ptoHeat = 0
    local hydraulicHeat = 0

    if isMotorStarted == false then
        return 0, loadFactor, hydrostaticFactor, wheelSlipFactor, accFactor, cvtSlipActive, cvtSlipLocked, idleHeat, ptoHeat, hydraulicHeat
    end

    idleHeat = (C.TRANS_IDLE_HEAT + C.TRANS_PUMP_HEAT) * (1 + math.clamp(motorRpm, 0.0, 1.0))

    local currentSpeed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
    local maxForwardSpeed = sanitizeNumber(motor:getMaximumForwardSpeed(), 1, 0.001, 1000)
    local speedRatio = math.clamp(currentSpeed / (maxForwardSpeed * 3.6), 0.0, 1.0)

    local accelerationAxis = vehicle.getAccelerationAxis ~= nil and sanitizeNumber(vehicle:getAccelerationAxis(), 0, -1, 1) or 0
    local cruiseControlAxis = vehicle.getCruiseControlAxis ~= nil and sanitizeNumber(vehicle:getCruiseControlAxis(), 0, -1, 1) or 0

    if accelerationAxis > 0 or cruiseControlAxis > 0 then
        local rotAcceleration = sanitizeNumber(motor.motorRotAccelerationSmoothed, 0, -1000000, 1000000)
        local rotAccelerationLimit = sanitizeNumber(motor.motorRotationAccelerationLimit, 1, 0.001, 1000000)
        accFactor = math.clamp(5 * motorRpm * math.clamp(rotAcceleration / rotAccelerationLimit, 0.0, 1.0), 1.0, 2.0)
    end

    -- extra load heat below the hydrostatic speed, variable transmissions pulling only
    if (accelerationAxis > 0 or cruiseControlAxis > 0) and (RMS_Utils.hasCVTTransmission(vehicle) or RMS_Utils.hasCVTAddon(vehicle)) then
        local hydrostaticShare = math.clamp(1 - currentSpeed / math.max(C.TRANS_HYDROSTATIC_MAX_SPEED, 0.001), 0.0, 1.0)
        hydrostaticFactor = 1 + C.TRANS_HYDROSTATIC_MAX_BOOST * (hydrostaticShare ^ 2)
    end

    -- cvt slip only heats while the ratio sits at its minimum below eighty percent of top speed
    if spec.activeEffects.CVT_SLIP_EFFECT ~= nil and spec.activeEffects.CVT_SLIP_EFFECT.value > 0 then
        cvtSlipActive = true
        local minGearRatio = sanitizeNumber(motor:getMinMaxGearRatio(), 1, 0.001, 1000000)
        local gearRatio = sanitizeNumber(motor.gearRatio, minGearRatio, 0.01, 1000000)
        local isSliping = (1 - minGearRatio / gearRatio <= 0.02) and speedRatio < 0.8
        if isSliping then
            cvtSlipLocked = true
            hydrostaticFactor = hydrostaticFactor * 2.0
        end
    end

    -- wheel slip only heats in a straight line
    local isTurning = RMS_Drivetrain.getIsTurning(vehicle)
    if not isTurning and spec.wheelSlipIntensity ~= nil and spec.wheelSlipIntensity > 0.05 then
        local wheelSlipIntensity = sanitizeNumber(spec.wheelSlipIntensity, 0, 0, 10)
        local avgTireGroundFrictionCoeff = sanitizeNumber(spec.avgTireGroundFrictionCoeff, 0, 0, 10)
        wheelSlipFactor = math.min(wheelSlipFactor + (wheelSlipIntensity / 2) * (avgTireGroundFrictionCoeff ^ 2), 1.4)
    end

    if spec.isHydraulicActive then
        hydraulicHeat = C.HYDRAULIC_OPERATING_HEAT
            + sanitizeNumber(spec.extraHydraulicHeat, 0, -C.HYDRAULIC_OPERATING_HEAT, 1000)
    end

    local maxHeat = C.TRANS_MAX_HEAT + sanitizeNumber(spec.extraTransmissionHeat, 0, -C.TRANS_MAX_HEAT, 1000)
    local loadHeatRange = math.max(maxHeat - idleHeat, 0)
    ptoHeat = loadHeatRange * ptoShare * C.TRANS_PTO_HEAT_SHARE
    local heat = idleHeat + loadHeatRange * loadFactor * hydrostaticFactor * accFactor * wheelSlipFactor + ptoHeat + hydraulicHeat

    return heat, loadFactor, hydrostaticFactor, wheelSlipFactor, accFactor, cvtSlipActive, cvtSlipLocked, idleHeat, ptoHeat, hydraulicHeat
end

---Returns the transmission thermostat opening the oil temperature calls for
-- @param table spec vehicle spec
-- @param float temperature oil temperature
-- @return float state opening between 0 and 1
local function getTransmissionThermostatState(spec, temperature)
    local C = RMS_Config.THERMAL
    if spec.transmissionThermostatStuckedPosition ~= nil then
        return sanitizeNumber(spec.transmissionThermostatStuckedPosition, 0, 0, 1)
    end

    -- thermostat opening temperature, raised by wear
    local health = math.clamp(sanitizeNumber(spec.transmissionThermostatHealth, 1.0, 0, 1), 0.0, 1.0)
    local openTemp = C.TRANS_THERMOSTAT_MIN_TEMP + (1 - health) * C.TRANS_THERMOSTAT_HEALTH_LAG
    local range = math.max(C.TRANS_THERMOSTAT_MAX_TEMP - C.TRANS_THERMOSTAT_MIN_TEMP, 0.001)
    return math.clamp((sanitizeNumber(temperature, 20, -80, 180) - openTemp) / range, 0.0, 1.0)
end

---Returns the transmission cooling from convection, its oil cooler and driving speed
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param float eviromentTemp ambient temperature
-- @param float dirt radiator clogging ratio
-- @param boolean isMotorStarted true while the motor runs
-- @return float cooling total cooling
-- @return float coolerCooling oil cooler share
-- @return float convectionCooling convection share
-- @return float speedCooling speed share
local function getTransmissionCooling(vehicle, spec, eviromentTemp, dirt, isMotorStarted)
    local C = RMS_Config.THERMAL
    local rawTransmissionTemperature = sanitizeNumber(spec.rawTransmissionTemperature, eviromentTemp, -80, 180)
    local deltaTemp = math.max(0, rawTransmissionTemperature - eviromentTemp)
    local convectionCooling = C.CONVECTION_FACTOR * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    local speedCooling = getSpeedCooling(vehicle)

    -- motor stopped, convection only
    if isMotorStarted == false then
        if rawTransmissionTemperature < C.TRANS_THERMOSTAT_MAX_TEMP then
            return convectionCooling / C.COOLING_SLOWDOWN_POWER, 0, convectionCooling, speedCooling
        else
            return convectionCooling, 0, convectionCooling, speedCooling
        end
    end

    local thermostatState = sanitizeNumber(spec.transmissionThermostatState, 0, 0, 1)
    local fanRange = math.max(C.TRANS_FAN_MAX_TEMP - C.TRANS_THERMOSTAT_MAX_TEMP, 0.001)
    local fanBoost = 1 + C.TRANS_FAN_MAX_BOOST * math.clamp((rawTransmissionTemperature - C.TRANS_THERMOSTAT_MAX_TEMP) / fanRange, 0.0, 1.0)
    local oilFactor = RMS_Utils.getFluidCapacityFactor(spec.transmissionOilLevel, RMS_Config.FLUIDS.MIN_COOLING_FACTOR)
    local dirtCoolerMaxCooling = C.TRANS_COOLER_MAX_COOLING * oilFactor * (1 - C.MAX_DIRT_INFLUENCE * (dirt ^ 2))
    local coolerCooling = dirtCoolerMaxCooling * thermostatState * fanBoost * (deltaTemp ^ C.DELTATEMP_FACTOR_DEGREE)
    return (coolerCooling + convectionCooling) * (1 + speedCooling), coolerCooling, convectionCooling, speedCooling
end

---Advances the raw transmission temperature by heat minus cooling, then updates its thermostat
-- @param float dt time since last call in ms
-- @param table spec vehicle spec
-- @param boolean isMotorStarted true while the motor runs
-- @param float motorLoad motor load ratio
-- @param float motorRpm motor rpm ratio
-- @param float eviromentTemp ambient temperature
-- @param float dirt radiator clogging ratio
-- @return table? dbg transmission temperature debug data
function RMS_Thermal:updateTransmissionThermalModel(dt, spec, isMotorStarted, motorLoad, motorRpm, eviromentTemp, dirt)
    local C = RMS_Config.THERMAL
    local heat, cooling = 0, 0
    local coolerCooling, convectionCooling = 0, 0
    local speedCooling = 0
    local loadFactor = 0
    local hydrostaticFactor = 1.0
    local wheelSlipFactor = 1.0
    local accFactor = 1.0
    local cvtSlipActive = false
    local cvtSlipLocked = false
    local idleHeat = 0
    local ptoHeat = 0
    local hydraulicHeat = 0

    local dbg = spec.debugData.transmissionTemp

    heat, loadFactor, hydrostaticFactor, wheelSlipFactor, accFactor, cvtSlipActive, cvtSlipLocked, idleHeat, ptoHeat, hydraulicHeat = getTransmissionHeat(self, spec, isMotorStarted, motorLoad, motorRpm)
    cooling, coolerCooling, convectionCooling, speedCooling = getTransmissionCooling(self, spec, eviromentTemp, dirt, isMotorStarted)

    local safeDt = sanitizeNumber(dt, 0, 0)
    spec.rawTransmissionTemperature = sanitizeNumber(spec.rawTransmissionTemperature + (heat - cooling) * (safeDt / 1000) * C.TRANS_TEMPERATURE_CHANGE_SPEED * C.TRANS_TEMPERATURE_CHANGE_MULTIPLIER, eviromentTemp, -80, 180)
    spec.rawTransmissionTemperature = math.max(spec.rawTransmissionTemperature, eviromentTemp)

    local rawTransmissionTemp = sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, eviromentTemp, -80, 180)
    if isMotorStarted then
        spec.transmissionThermostatState = getTransmissionThermostatState(spec, rawTransmissionTemp)
    else
        spec.transmissionThermostatState = 0.0
    end

    if dbg then
        dbg.totalHeat = heat
        dbg.totalCooling = cooling
        dbg.coolerCooling = coolerCooling
        dbg.speedCooling = speedCooling
        dbg.convectionCooling = convectionCooling
        dbg.loadFactor = loadFactor
        dbg.hydrostaticFactor = hydrostaticFactor
        dbg.wheelSlipFactor = wheelSlipFactor
        dbg.accFactor = accFactor
        dbg.cvtSlipActive = cvtSlipActive and 1 or 0
        dbg.cvtSlipLocked = cvtSlipLocked and 1 or 0
        dbg.extraTransmissionHeat = spec.extraTransmissionHeat or 0
        dbg.idleHeat = idleHeat
        dbg.ptoHeat = ptoHeat
        dbg.hydraulicHeat = hydraulicHeat
    end

    return dbg
end

---Returns the new thermostat opening, a wax curve before the type year divider and a PID after it
-- @param float dt time since last call in ms
-- @param float currentTemp current temperature
-- @param float targetTemp regulated temperature
-- @param table? pidData PID state, carried between calls
-- @param float thermostatHealth thermostat health ratio
-- @param integer year vehicle production year
-- @param float? stuckedPosition opening the thermostat is stuck at
-- @param table? debugData debug data filled in place
-- @return float state opening between 0 and 1
function RMS_Thermal.getNewTermostatState(dt, currentTemp, targetTemp, pidData, thermostatHealth, year, stuckedPosition, debugData)
    if stuckedPosition ~= nil then
        return sanitizeNumber(stuckedPosition, 0, 0, 1)
    end

    local C = RMS_Config.THERMAL
    local dtSeconds = math.max(sanitizeNumber(dt, 0, 0) / 1000, 0.001)
    currentTemp = sanitizeNumber(currentTemp, targetTemp or 80, -80, 180)
    targetTemp = sanitizeNumber(targetTemp, 80, -80, 180)
    thermostatHealth = sanitizeNumber(thermostatHealth, 1.0, 0, 1)
    year = sanitizeNumber(year, 2000, 1900, 2200)
    if pidData == nil then
        pidData = {integral = 0, lastError = 0}
    end
    pidData.integral = sanitizeNumber(pidData.integral, 0, -C.PID_MAX_INTEGRAL, C.PID_MAX_INTEGRAL)
    pidData.lastError = sanitizeNumber(pidData.lastError, 0, -300, 300)
    pidData.mechPos = sanitizeNumber(pidData.mechPos, 0, 0, 1)

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

        -- the integral only accumulates while the control signal stays inside its range
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
    local yearFactor = isMechanical
        and (year - C.MECHANIC_THERMOSTAT_MIN_YEAR) * C.MECHANIC_THERMOSTAT_WAX_YEAR_SLOPE
        or (year - C.THERMOSTAT_TYPE_YEAR_DIVIDER) * C.ELECTRONIC_THERMOSTAT_WAX_YEAR_SLOPE

    local waxSpeed = math.clamp(baseSpeed + yearFactor, C.MECHANIC_THERMOSTAT_MIN_WAX_SPEED, C.ELECTRONIC_THERMOSTAT_MAX_WAX_SPEED)
    waxSpeed = waxSpeed * math.max(0.2, thermostatHealth)

    -- the opening moves at the wax speed, then snaps to the nearest stiction step
    local currentMechPos = pidData.mechPos or 0.0
    local delta = targetPos - currentMechPos
    local maxMove = waxSpeed * dtSeconds

    if math.abs(delta) > maxMove then
        delta = maxMove * (delta > 0 and 1 or -1)
    end

    local newPos = math.clamp(currentMechPos + delta, 0.0, maxOpening)
    pidData.mechPos = newPos

    local baseStiction = isMechanical
        and (C.MECHANIC_THERMOSTAT_MAX_STICTION - (year - C.MECHANIC_THERMOSTAT_MIN_YEAR) * C.STICTION_YEAR_SLOPE)
        or (C.ELECTRONIC_THERMOSTAT_MAX_STICTION - (year - C.THERMOSTAT_TYPE_YEAR_DIVIDER) * C.STICTION_YEAR_SLOPE)
    local stiction = math.clamp(baseStiction, C.ELECTRONIC_THERMOSTAT_MIN_STICTION, C.MECHANIC_THERMOSTAT_MAX_STICTION)

    stiction = stiction * (2 - math.max(0.5, thermostatHealth))

    if debugData then
        debugData.stiction = stiction
        debugData.waxSpeed = waxSpeed
    end

    return math.clamp(math.floor(newPos / stiction) * stiction, 0.0, maxOpening)
end
