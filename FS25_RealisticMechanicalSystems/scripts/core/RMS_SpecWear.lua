-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Per system wear and stress accumulation of a vehicle

local hasCVTTransmission = RMS_Utils.hasCVTTransmission
local hasCVTAddon = RMS_Utils.hasCVTAddon
local ensureFactorStats = RealisticMechanicalSystems.ensureFactorStats
local getColdEngineStress = RealisticMechanicalSystems.getColdEngineStress
local isMissionVehicle = RealisticMechanicalSystems.isMissionVehicle

---Resolves a system name to the key actually present in the spec, matching case insensitively
-- @param table? spec vehicle spec
-- @param string systemName system name
-- @return string key resolved system key
local function resolveSystemKey(spec, systemName)
    if spec == nil or spec.systems == nil or type(systemName) ~= "string" then
        return systemName
    end

    if spec.systems[systemName] ~= nil then
        return systemName
    end

    local loweredSystemName = string.lower(systemName)
    local weights = RMS_Config ~= nil and RMS_Config.CORE ~= nil and RMS_Config.CORE.SYSTEM_WEIGHTS or nil
    if type(weights) == "table" then
        for weightedKey, _ in pairs(weights) do
            if string.lower(tostring(weightedKey)) == loweredSystemName and spec.systems[weightedKey] ~= nil then
                return weightedKey
            end
        end
    end

    for existingKey, _ in pairs(spec.systems) do
        if string.lower(tostring(existingKey)) == loweredSystemName then
            return existingKey
        end
    end

    return systemName
end

---Returns the system entry, creating it and clamping its condition and stress
-- @param table spec vehicle spec
-- @param string systemName system name
-- @return table systemData system condition and stress
local function ensureSystemData(spec, systemName)
    if spec.systems == nil then
        spec.systems = {}
    end

    systemName = resolveSystemKey(spec, systemName)

    local systemData = spec.systems[systemName]
    if type(systemData) ~= "table" then
        systemData = {
            condition = tonumber(systemData) or 1.0,
            stress = 0.0
        }
        spec.systems[systemName] = systemData
    end

    systemData.condition = math.clamp(tonumber(systemData.condition) or 1.0, 0.001, 1.0)
    systemData.stress = math.max(tonumber(systemData.stress) or 0.0, 0.0)

    return systemData
end

---Returns the extra wear caused by a service level below its expiry threshold
-- @param float? serviceLevel remaining service level
-- @param float? serviceMultiplier system sensitivity to an expired service
-- @return float factor additional wear, 0 above the threshold
local function getExpiredServiceFactor(serviceLevel, serviceMultiplier)
    if serviceLevel == nil then
        return 0.0
    end

    if serviceLevel < RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD then
        local severity = math.clamp(
            (RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD - serviceLevel) / RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD,
            0.0,
            1.0
        )
        local serviceExpireWear = severity * (serviceMultiplier or 0)
        return serviceExpireWear
    end

    return 0.0
end

---Consumes the service level, faster under load and slower while parked, under a roof most of all
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateServiceLevel(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if isMissionVehicle(self) then
        return
    end

    local wearRate = RMS_Config.CORE.BASE_SERVICE_WEAR

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        wearRate = wearRate * (1 + spec.extraServiceWear) 
    else
        if spec.isUnderRoof then 
            wearRate = wearRate * RMS_Config.CORE.UNDER_ROOF_DOWNTIME_MULTIPLIER 
        else
            wearRate = wearRate * RMS_Config.CORE.DOWNTIME_MULTIPLIER
        end
    end  

    wearRate = wearRate / spec.reliability
    
    local newLevel = spec.serviceLevel -  wearRate / (60 * 60 * 1000) * dt
    spec.serviceLevel = math.max(newLevel, 0)

    if RMS_Config.DEBUG then
        if spec.debugData == nil then
            spec.debugData = {}
        end
        if spec.debugData.service == nil then
            spec.debugData.service = {}
        end

        local dbg = spec.debugData.service
        dbg.totalWearRate = wearRate
    end
end

---Recomputes the overall condition as the weighted mean of the enabled systems
function RealisticMechanicalSystems:updateConditionLevel()
    local spec = self.spec_RealisticMechanicalSystems
    local weightedCondition = 0
    local totalEnabledWeight = 0
    local systemWeights = RMS_Config.CORE.SYSTEM_WEIGHTS or {}

    for systemName, systemData in pairs(spec.systems) do
        if systemData.enabled ~= false then
            local weight = tonumber(systemWeights[systemName]) or 0
            if weight > 0 then
                local systemCondition = tonumber(systemData.condition) or 1.0
                weightedCondition = weightedCondition + systemCondition * weight
                totalEnabledWeight = totalEnabledWeight + weight
            end
        end
    end

    local condition = 1.0
    if totalEnabledWeight > 0 then
        condition = weightedCondition / totalEnabledWeight
    end

    spec.conditionLevel = math.clamp(condition, 0.001, 1.0)
end

---Applies one wear step to a system, lowering its condition and raising its stress above the base rate
-- @param float dt time since last call in ms
-- @param string systemName system name
-- @param float? wearRate wear rate, the reliability based rate when omitted
-- @param table? debugFactors per factor contributions recorded for the statistics
function RealisticMechanicalSystems:updateSystemConditionAndStress(dt, systemName, wearRate, debugFactors)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    systemName = resolveSystemKey(spec, systemName)

    local reliability = math.max(spec.reliability or 1.0, 0.001)
    local baseWearRate = 1.0 / reliability
    local systemData = ensureSystemData(spec, systemName)
    wearRate = tonumber(wearRate) or baseWearRate
    wearRate = wearRate * (1 + spec.extraConditionWear) / reliability

    local stressMultipliers = RMS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS or {}
    local systemStressMultiplier = stressMultipliers[systemName] or 1.0
    local globalStressMultiplier = math.max(tonumber(RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER) or 1.0, 0.0)
    local dtMultiplier = RMS_Config.CORE.BASE_SYSTEMS_WEAR / (60 * 60 * 1000) * dt

    local conditionToRemove = wearRate * dtMultiplier
    local newCondition = (systemData.condition or 1.0) - conditionToRemove
    systemData.condition = math.clamp(newCondition, 0.001, 1.0)

    local stressToAdd = 0
    if not isMissionVehicle(self) then
        stressToAdd = math.max(wearRate - baseWearRate, 0) * dtMultiplier * systemStressMultiplier * globalStressMultiplier
    end
    systemData.stress = math.max((systemData.stress or 0) + stressToAdd, 0)

    local factorStats = ensureFactorStats(spec, self)
    local systemStats = factorStats[systemName]
    if type(systemStats) == "table" then
        systemStats.total = (tonumber(systemStats.total) or 0) + wearRate * dtMultiplier
        systemStats.stress = (tonumber(systemStats.stress) or 0) + stressToAdd

        if type(debugFactors) == "table" then
            for key, value in pairs(debugFactors) do
                local numericValue = tonumber(value)
                local alias = RealisticMechanicalSystems.FACTOR_STATS_ALIASES[tostring(key)]
                if numericValue ~= nil and alias ~= nil then
                    local factorDelta = (numericValue / reliability) * dtMultiplier
                    systemStats[alias] = (tonumber(systemStats[alias]) or 0) + factorDelta
                end
            end
        end
    end

    if RMS_Config.DEBUG and systemName ~= nil then
        if spec.debugData == nil then
            spec.debugData = {}
        end
        if spec.debugData[systemName] == nil then
            spec.debugData[systemName] = {}
        end

        local dbg = spec.debugData[systemName]
        dbg.condition = systemData.condition
        dbg.stress = systemData.stress
        dbg.totalWearRate = wearRate
        dbg.instantStressRate = dt > 0 and (stressToAdd * (60 * 60 * 1000) / dt) or 0

        if debugFactors ~= nil then
            for key, value in pairs(debugFactors) do
                dbg[key] = value
            end
        end
    end
end

---Removes a fixed amount of condition from a system at once
-- @param string system system name
-- @param float damageAmount condition removed
-- @param string? factorName factor credited in the statistics
function RealisticMechanicalSystems:applyInstantDamageToSystem(system, damageAmount, factorName)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system)
    systemKey = resolveSystemKey(spec, systemKey)

    if systemKey == nil or systemKey == "" or spec.systems[systemKey] == nil then
        return
    end

    local dmg = math.max(tonumber(damageAmount) or 0, 0)
    spec.systems[systemKey].condition = math.clamp((spec.systems[systemKey].condition or 1.0) - dmg, 0.001, 1.0)
    local stressToAdd = 0
    if not isMissionVehicle(self) then
        stressToAdd = dmg * (RMS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS[systemKey] or 1)
    end
    local stressCap = math.max(spec.systems[systemKey].condition or 0, RMS_Config.CORE.CONDITION_EFFECTIVE_FLOOR or 0)
    spec.systems[systemKey].stress = math.clamp((spec.systems[systemKey].stress or 0) + stressToAdd, 0, stressCap)

    local factorStats = ensureFactorStats(spec, self)
    local systemStats = factorStats[systemKey]
    if type(systemStats) == "table" then
        systemStats.total = (tonumber(systemStats.total) or 0) + dmg
        systemStats.stress = (tonumber(systemStats.stress) or 0) + stressToAdd

        local alias = RealisticMechanicalSystems.FACTOR_STATS_ALIASES[tostring(factorName)]
        if alias ~= nil then
            systemStats[alias] = (tonumber(systemStats[alias]) or 0) + dmg
        end
    end
end

-- systems
---Wears the engine on motor load, lugging, air intake clogging, cold and hot running, and an expired service
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateEngineSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local spec_motorized = self.spec_motorized
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    local motorLoadFactor, luggingFactor, expiredServiceFactor, coldMotorFactor, hotMotorFactor, airFilterCloggingFactor = 0, 0, 0, 0, 0, 0
    local baseWearRate = 1.0
    local wearRate = baseWearRate
    local rpmLoad = 0
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.engine.name)
    local systemData = spec.systems.engine

    if not systemData.enabled then
        return
    end

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() and not spec.isElectricVehicle then
        local motorLoad = self:getMotorLoadPercentage()
        local dynamicMotorLoad = spec.dynamicMotorLoad
        local lastRpm = spec_motorized.motor:getLastModulatedMotorRpm()
        local maxRpm = spec_motorized.motor.maxRpm
        rpmLoad = lastRpm / maxRpm

        -- overload factor
        if dynamicMotorLoad > C.MOTOR_OVERLOADED_THRESHOLD then
            motorLoadFactor = RMS_Utils.calculateQuadraticMultiplier(dynamicMotorLoad, C.MOTOR_OVERLOADED_THRESHOLD, false, C.MOTOR_OVERLOADED_MAX_EFFECT)
            motorLoadFactor = motorLoadFactor * (C.MOTOR_OVERLOADED_MULTIPLIER or 0)
            wearRate = wearRate + motorLoadFactor
        end

        -- lugging factor
        if dynamicMotorLoad > C.LUGGING_MOTORLOAD_THRESHOLD and rpmLoad < C.LUGGING_RPM_THRESHOLD and self:getLastSpeed() > 0.5 then
            local maxDiff = 0.6
            local minDiff = math.clamp(C.LUGGING_MOTORLOAD_THRESHOLD - C.LUGGING_RPM_THRESHOLD, 0, maxDiff)
            local currentDiff = math.clamp(dynamicMotorLoad - rpmLoad, 0.0, 1.0)
            luggingFactor = RMS_Utils.calculateQuadraticMultiplier(currentDiff, minDiff, false, maxDiff)
            luggingFactor = luggingFactor * (C.LUGGING_MULTIPLIER or 0)
            wearRate = wearRate + luggingFactor
        end

        -- air intake clogging factor
        if spec.airFilterClogging > C.AIR_FILTER_CLOGGING_THRESHOLD then
            airFilterCloggingFactor = RMS_Utils.calculateQuadraticMultiplier(spec.airFilterClogging, C.AIR_FILTER_CLOGGING_THRESHOLD, false)
            airFilterCloggingFactor = airFilterCloggingFactor * (C.AIR_FILTER_CLOGGING_MULTIPLIER or 0)
            wearRate = wearRate + airFilterCloggingFactor
        end

        -- cold engine factor
        local coldEngineStress = getColdEngineStress(self)
        if coldEngineStress > 0 then
            coldMotorFactor = coldEngineStress * C.COLD_MOTOR_MULTIPLIER
            wearRate = wearRate + coldMotorFactor

        -- overheating engine factor
        elseif (spec.engineTemperature or -99) > C.OVERHEAT_MOTOR_THRESHOLD and motorLoad > 0.3 and not spec.isElectricVehicle then
            hotMotorFactor = RMS_Utils.calculateQuadraticMultiplier(spec.engineTemperature, C.OVERHEAT_MOTOR_THRESHOLD, false, 120)
            local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.3, false)
            hotMotorFactor = hotMotorFactor * (C.OVERHEAT_MOTOR_MULTIPLIER or 0) * motorLoadInf
            hotMotorFactor = math.min(hotMotorFactor, C.OVERHEAT_MOTOR_MULTIPLIER or hotMotorFactor)
            wearRate = wearRate + hotMotorFactor
        end

        -- idling
        if motorLoad < C.MOTOR_IDLING_THRESHOLD and self:getLastSpeed() < 0.003 then
            wearRate = wearRate * C.MOTOR_IDLING_MULTIPLIER
        end

        expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        if spec.isUnderRoof then 
            wearRate = wearRate * RMS_Config.CORE.UNDER_ROOF_DOWNTIME_MULTIPLIER 
        else
            wearRate = wearRate * RMS_Config.CORE.DOWNTIME_MULTIPLIER
        end
    end

    -- engine oil shortage factor
    local lowFluidFactor = 0
    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        lowFluidFactor = RMS_Utils.getFluidShortage(spec.engineOilLevel) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER
        wearRate = wearRate + lowFluidFactor
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        motorLoadFactor = motorLoadFactor,
        lowFluidFactor = lowFluidFactor,
        luggingFactor = luggingFactor,
        dynamicMotorLoad = spec.dynamicMotorLoad,
        airFilterCloggingFactor = airFilterCloggingFactor,
        expiredServiceFactor = expiredServiceFactor,
        coldMotorFactor = coldMotorFactor,
        hotMotorFactor = hotMotorFactor,
        airFilterClogging = spec.airFilterClogging,
        engineTemperature = spec.engineTemperature,
        rpmLoad = rpmLoad
    })
end

---Wears the transmission on pull overload, trailer mass, lugging, wheel slip, drivetrain windup, oil temperature and an expired service
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateTransmissionSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local spec_motorized = self.spec_motorized
    local spec_wheels = self.spec_wheels
    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    local systemData = spec.systems.transmission
    systemData.pullOverloadTimer = tonumber(systemData.pullOverloadTimer) or 0
    local vehicleHaveCVT = hasCVTTransmission(self)
    local isMotorStarted = self.getIsMotorStarted ~= nil and self:getIsMotorStarted()
    local dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or 0
    local transTemp = spec.transmissionTemperature or -99
    local expiredServiceFactor, pullOverloadFactor, luggingFactor, heavyTrailerFactor, wheelSlipFactor,  coldTransAbuse, hotTransFactor = 0, 0, 0, 0, 0, 0, 0
    local drivetrainWindupFactor = 0
    local wearRate = 1.0
    local brakeState = spec.chassisBrakeState
    local isTruck = spec.isTruck == true
    local trailerMass = math.max(brakeState.trailerMass, 0)
    local hpHeavyTrailerRatio = isTruck
        and brakeState.hpGrossMassRatio
        or brakeState.hpTrailerMassRatio
    local heavyTrailerRatioThreshold, heavyTrailerFullEffectRatio = RMS_Utils.getHeavyTrailerRatioLevels(isTruck)
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.transmission.name)
    
    if not systemData.enabled then
        return
    end

    if isMotorStarted and not spec.isElectricVehicle then
        -- cold transmission abuse, once per cold period
        if transTemp >= C.COLD_TRANSMISSION_THRESHOLD then
            spec.coldTransAbuseDone = false
        end
        if self.isServer and not spec.coldTransAbuseDone and transTemp < C.COLD_TRANSMISSION_THRESHOLD and dynamicMotorLoad >= C.COLD_TRANSMISSION_LOAD_THRESHOLD then
            spec.coldTransAbuseTimer = math.min((spec.coldTransAbuseTimer or 0) + dt, C.COLD_TRANSMISSION_ABUSE_DURATION)
            if spec.coldTransAbuseTimer >= C.COLD_TRANSMISSION_ABUSE_DURATION then
                spec.coldTransAbuseTimer = 0
                spec.coldTransAbuseDone = true
                self:applyInstantDamageToSystem(systemData.name, C.COLD_TRANSMISSION_DAMAGE, "coldTransFactor")
            end
        else
            spec.coldTransAbuseTimer = 0
        end
        coldTransAbuse = (spec.coldTransAbuseTimer or 0) / math.max(C.COLD_TRANSMISSION_ABUSE_DURATION, 1)
    end

    if hasCVTAddon(self) and isMotorStarted then
        local spec_CVTaddon = self.spec_CVTaddon

        local currentCVTdamage = math.clamp(tonumber(spec_CVTaddon.CVTdamage) or 0, 0, 100)
        local prevCVTdamage = math.clamp(tonumber(spec._prevCVTdamage) or currentCVTdamage, 0, 100)
        local prevStress = math.max(tonumber(spec._prevStress) or 0, 0)

        local cvtDamageDelta = math.max(currentCVTdamage - prevCVTdamage, 0)
        local normalizedCVTdamage = currentCVTdamage / 100
        local normalizedDelta = cvtDamageDelta / 100

        local systemStressMultiplier = RMS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS[systemKey] or 1.0
        local globalStressMultiplier = math.max(tonumber(RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER) or 1.0, 0.001)
        local divisor = math.max(systemStressMultiplier * globalStressMultiplier, 0.001)

        local currentCondition = math.clamp(tonumber(systemData.condition) or 1.0, 0.001, 1.0)
        local conditionToRemove = normalizedDelta / divisor
        local newCondition = math.clamp(currentCondition - conditionToRemove, 0.001, 1.0)

        local currentStress = systemData.stress or 0
        local newStress = currentStress
        if not isMissionVehicle(self) then
            newStress = math.clamp(currentStress + normalizedDelta, 0, newCondition)
        end
        local previousStress = math.clamp(tonumber(systemData.stress) or 0, 0, math.max(currentCondition, 0.001))

        systemData.condition = newCondition
        systemData.stress = newStress

        if isMissionVehicle(self) then
            spec._prevCVTdamage = currentCVTdamage
        else
            spec_CVTaddon.CVTdamage = newStress / math.max(newCondition, 0.001) * 100
            spec._prevCVTdamage = spec_CVTaddon.CVTdamage
        end
        spec._prevStress = newStress

        local factorStats = ensureFactorStats(spec, self)
        local systemStats = factorStats[systemKey]
        if type(systemStats) == "table" then
            systemStats.total = (tonumber(systemStats.total) or 0) + conditionToRemove
            systemStats.stress = (tonumber(systemStats.stress) or 0) + math.max(newStress - previousStress, 0)
        end

        local motorLoad = self:getMotorLoadPercentage()
        local speed = self:getLastSpeed()
        if motorLoad < RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_IDLING_THRESHOLD and speed < 0.003 then
            wearRate = wearRate * C.TRANSMISSION_IDLING_MULTIPLIER
        end

    elseif isMotorStarted and not spec.isElectricVehicle then
        local motorLoad = self:getMotorLoadPercentage()
        local lastRpm = spec_motorized.motor:getLastModulatedMotorRpm()
        local maxRpm = spec_motorized.motor.maxRpm
        local rpmLoad = lastRpm / maxRpm
        local speed = self:getLastSpeed()
        
        -- pull overload
        local pullOverloadTargetTimer = 0
        if dynamicMotorLoad >= C.PULL_OVERLOAD_THRESHOLD then
            local timerMax = tonumber(C.PULL_OVERLOAD_TIMER_MAX_EFFECT) or 90
            local timerMid = tonumber(C.PULL_OVERLOAD_TIMER_THRESHOLD) or 60
            local timerMin = math.max(timerMid - (timerMax - timerMid), 0)
            local loadMaxForTimer = 1.15
            local loadRange = math.max(loadMaxForTimer - C.PULL_OVERLOAD_THRESHOLD, 0.001)
            local loadRatio = math.clamp((dynamicMotorLoad - C.PULL_OVERLOAD_THRESHOLD) / loadRange, 0.0, 1.0)
            pullOverloadTargetTimer = timerMin + (timerMax - timerMin) * loadRatio
        end

        systemData.pullOverloadTimerMax = pullOverloadTargetTimer
        systemData.pullOverloadTimerMin = dynamicMotorLoad < C.PULL_OVERLOAD_THRESHOLD and 0 or pullOverloadTargetTimer

        if systemData.pullOverloadTimer < pullOverloadTargetTimer then
            systemData.pullOverloadTimer = math.min(systemData.pullOverloadTimer + dt / 1000, pullOverloadTargetTimer)
        elseif systemData.pullOverloadTimer > pullOverloadTargetTimer then
            systemData.pullOverloadTimer = math.max(systemData.pullOverloadTimer - dt / 1000, pullOverloadTargetTimer)
        end

        if speed > 0.5 and systemData.pullOverloadTimer > 0 then
            pullOverloadFactor = RMS_Utils.calculateQuadraticMultiplier(systemData.pullOverloadTimer, 0, false, C.PULL_OVERLOAD_TIMER_MAX_EFFECT)
            pullOverloadFactor = math.clamp(pullOverloadFactor * dynamicMotorLoad * C.PULL_OVERLOAD_MULTIPLIER, 0, C.PULL_OVERLOAD_MULTIPLIER * 5)
            wearRate = wearRate + pullOverloadFactor
        end
 
        -- lugging factor
        if dynamicMotorLoad > C.LUGGING_MOTORLOAD_THRESHOLD and rpmLoad < C.LUGGING_RPM_THRESHOLD and speed > 0.5 then
            local maxDiff = 0.6
            local minDiff = math.clamp(C.LUGGING_MOTORLOAD_THRESHOLD - C.LUGGING_RPM_THRESHOLD, 0, maxDiff)
            local currentDiff = math.clamp(dynamicMotorLoad - rpmLoad, 0.0, 1.0)
            luggingFactor = RMS_Utils.calculateQuadraticMultiplier(currentDiff, minDiff, false, maxDiff)
            luggingFactor = luggingFactor * C.LUGGING_MULTIPLIER
            wearRate = wearRate + luggingFactor
            -- tutorial timer
            spec.luggingTutorialTimer = math.min((spec.luggingTutorialTimer or 0) + dt, 5000)
        else
             spec.luggingTutorialTimer = math.max((spec.luggingTutorialTimer or 0) - dt, 0)
        end

        -- heavy trailer factor
        if trailerMass > 0.1 and hpHeavyTrailerRatio < heavyTrailerRatioThreshold and motorLoad > C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD and speed > 0.5 then
            heavyTrailerFactor = RMS_Utils.calculateQuadraticMultiplier(hpHeavyTrailerRatio, heavyTrailerRatioThreshold, true, heavyTrailerFullEffectRatio)
            local loadRange = math.max(1.0 - C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD, 0.001)
            local loadRatio = math.clamp((motorLoad - C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD) / loadRange, 0, 1.0)
            heavyTrailerFactor = math.max(heavyTrailerFactor * C.HEAVY_TRAILER_MULTIPLIER * loadRatio, 0)
            heavyTrailerFactor = math.min(heavyTrailerFactor, C.HEAVY_TRAILER_MULTIPLIER or heavyTrailerFactor)
            wearRate = wearRate + heavyTrailerFactor
        end

        -- wheel slip factor
        local isTurning = RMS_Drivetrain.getIsTurning(self)
        if not isTurning and spec.wheelSlipIntensity > C.WHEEL_SLIP_THRESHOLD and speed < 20 and motorLoad > 0.5 then
            local groundFrictionCoef = spec.avgTireGroundFrictionCoeff
            wheelSlipFactor = RMS_Utils.calculateQuadraticMultiplier(spec.wheelSlipIntensity, C.WHEEL_SLIP_THRESHOLD, false)
            wheelSlipFactor = math.max(wheelSlipFactor * (C.WHEEL_SLIP_MULTIPLIER or 0) * (groundFrictionCoef ^ 2) * motorLoad, 0)
            wearRate = wearRate + wheelSlipFactor
            -- tutorial timer
            spec.wheelSlipTutorialTimer = math.min((spec.wheelSlipTutorialTimer or 0) + dt, 3000)
        else
             spec.wheelSlipTutorialTimer = math.max((spec.wheelSlipTutorialTimer or 0) - dt, 0)
        end

        -- driveline windup factor (locked differentials + steering on grippy ground)
        drivetrainWindupFactor = RMS_Drivetrain.getWindupWearFactor(self)
        if drivetrainWindupFactor > 0 then
            wearRate = wearRate + drivetrainWindupFactor
        end

        if vehicleHaveCVT then
            -- overheating CVT factor
            if transTemp > C.OVERHEAT_TRANSMISSION_THRESHOLD and motorLoad > 0.3 and not spec.isElectricVehicle then
                hotTransFactor = RMS_Utils.calculateQuadraticMultiplier(transTemp, C.OVERHEAT_TRANSMISSION_THRESHOLD, false, 120)
                local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(rpmLoad, 0.5, false)
                hotTransFactor = hotTransFactor * C.OVERHEAT_TRANSMISSION_MAX_MULTIPLIER * motorLoadInf
                hotTransFactor = math.min(hotTransFactor, C.OVERHEAT_TRANSMISSION_MAX_MULTIPLIER or hotTransFactor)
                wearRate = wearRate + hotTransFactor
            end
        end

        -- idling
        if motorLoad < RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_IDLING_THRESHOLD and speed < 0.003 then
            wearRate = wearRate * C.TRANSMISSION_IDLING_MULTIPLIER
        end

        -- service
        expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER or RMS_Config.CORE.ENGINE_FACTOR_DATA.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        if hasCVTAddon(self) and not isMissionVehicle(self) then
            local spec_CVTaddon = self.spec_CVTaddon
            spec_CVTaddon.CVTdamage = systemData.stress / math.max(systemData.condition, 0.001) * 100
        end

        if spec.isUnderRoof then 
            wearRate = wearRate * RMS_Config.CORE.UNDER_ROOF_DOWNTIME_MULTIPLIER 
        else
            wearRate = wearRate * RMS_Config.CORE.DOWNTIME_MULTIPLIER
        end
    end

    -- transmission oil shortage factor
    local lowFluidFactor = 0
    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        lowFluidFactor = RMS_Utils.getFluidShortage(spec.transmissionOilLevel) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER
        wearRate = wearRate + lowFluidFactor
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        pullOverloadFactor = pullOverloadFactor,
        lowFluidFactor = lowFluidFactor,
        pullOverloadTimer = systemData.pullOverloadTimer,
        pullOverloadTimerMin = systemData.pullOverloadTimerMin,
        pullOverloadTimerMax = systemData.pullOverloadTimerMax,
        heavyTrailerFactor = heavyTrailerFactor,
        heavyTrailerMassRatio = hpHeavyTrailerRatio,
        heavyTrailerMassBasis = isTruck and "gcw" or "trailer",
        luggingFactor = luggingFactor,
        wheelSlipFactor = wheelSlipFactor,
        drivetrainWindupFactor = drivetrainWindupFactor,
        coldTransAbuse = coldTransAbuse,
        hotTransFactor = hotTransFactor
    })
end

---Wears the hydraulics on pump operation, lift load, vibration, cylinder work, oil temperature and an expired service
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateHydraulicsSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.hydraulics.name)
    local systemData = spec.systems.hydraulics
    local expiredServiceFactor = 0
    local C = RMS_Config.CORE.HYDRAULICS_FACTOR_DATA
    local heavyLiftFactor, operatingFactor, coldOilFactor, hotOilFactor, vibFactor = 0, 0, 0, 0, 0
    local wearRate = 0
    local vehicleMass = self.getTotalMass ~= nil and (self:getTotalMass(true) or 0) or 0
    local heavyLiftMassRatio = vehicleMass > 0 and math.max(spec.liftedMass or 0, 0) / vehicleMass or 0
    heavyLiftFactor = math.clamp(heavyLiftMassRatio, 0, 1)
    local vibState = spec.chassisVibState or {}
    local vibSignal = tonumber(vibState.smoothed) or 0
    local vibFieldMultiplier = tonumber(vibState.fieldMultiplier) or 1
    local vibConfig = RMS_Config.CORE.CHASSIS_FACTOR_DATA

    if not systemData.enabled then
        return
    end

    local motorStarted = self.getIsMotorStarted ~= nil and self:getIsMotorStarted()
    if motorStarted then
        wearRate = C.PUMP_WEAR_RATE + heavyLiftFactor
    end

    if motorStarted and spec.isImplementLifted and self:getLastSpeed() > 0.003 then
        local vibThreshold = tonumber(vibConfig.VIB_FACTOR_THRESHOLD) or 0.08
        if vibSignal > vibThreshold then
            local vibMaxSignal = tonumber(vibConfig.VIB_FACTOR_MAX_SIGNAL) or 0.36
            local vibMaxForCurve = math.max(vibMaxSignal, vibThreshold + 0.001)
            local vibMultiplier = (tonumber(vibConfig.VIB_FACTOR_MULTIPLIER) or 36.0) * vibFieldMultiplier
            vibFactor = RMS_Utils.calculateQuadraticMultiplier(vibSignal, vibThreshold, false, vibMaxForCurve)
            vibFactor = math.min(vibFactor * vibMultiplier, vibMultiplier)
            wearRate = wearRate + vibFactor
        end
    end

    if motorStarted and spec.isHydraulicActive then
        operatingFactor = math.max(1 - C.PUMP_WEAR_RATE, 0)
        wearRate = wearRate + operatingFactor
        local oilTemperature = tonumber(spec.transmissionTemperature) or 20
        if oilTemperature < C.COLD_OIL_THRESHOLD then
            coldOilFactor = RMS_Utils.calculateQuadraticMultiplier(oilTemperature, C.COLD_OIL_THRESHOLD, true)
                * C.COLD_OIL_MULTIPLIER
            wearRate = wearRate + coldOilFactor
        elseif oilTemperature > C.HOT_OIL_THRESHOLD then
            hotOilFactor = RMS_Utils.calculateQuadraticMultiplier(oilTemperature, C.HOT_OIL_THRESHOLD, false, 120)
                * C.HOT_OIL_MULTIPLIER
            hotOilFactor = math.min(hotOilFactor, C.HOT_OIL_MULTIPLIER)
            wearRate = wearRate + hotOilFactor
        end

        expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    end

    -- hydraulic fluid shortage factor
    local lowFluidFactor = 0
    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        lowFluidFactor = RMS_Utils.getFluidShortage(spec.hydraulicFluidLevel) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER
        wearRate = wearRate + lowFluidFactor
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        heavyLiftFactor = heavyLiftFactor,
        lowFluidFactor = lowFluidFactor,
        heavyLiftMassRatio = heavyLiftMassRatio,
        vibFactor = vibFactor,
        vibSignal = vibSignal,
        vibFieldMultiplier = vibFieldMultiplier,
        operatingFactor = operatingFactor,
        coldOilFactor = coldOilFactor,
        hotOilFactor = hotOilFactor,
        isHydraulicActive = spec.isHydraulicActive == true
    })
end

---Wears the PTO while active from its load and an expired service, recording engagement cycles for fault selection
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updatePtoSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemData = spec.systems.pto
    if systemData == nil or systemData.enabled == false then
        return
    end

    local C = RMS_Config.CORE.PTO_FACTOR_DATA
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemData.name)
    local wearRate = 0
    local expiredServiceFactor = 0
    local ptoLoadFactor = 0
    local ptoEngagementFactor = math.max(tonumber(spec.ptoEngagementPulseCount) or 0, 0)

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() and spec.isPtoActive then
        wearRate = 1
        local utilization = math.max(tonumber(spec.ptoUtilization) or 0, 0)
        if utilization > C.LOAD_FACTOR_THRESHOLD then
            ptoLoadFactor = RMS_Utils.calculatePtoLoadFactor(utilization, C)
            wearRate = wearRate + ptoLoadFactor
        end

        expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        isPtoActive = spec.isPtoActive == true,
        expiredServiceFactor = expiredServiceFactor,
        ptoLoadFactor = ptoLoadFactor,
        ptoEngagementFactor = ptoEngagementFactor,
        ptoTorque = spec.ptoTorque,
        ptoRpm = spec.ptoRpm,
        ptoPower = spec.ptoPower,
        ptoUtilization = spec.ptoUtilization,
        ptoMotorSideTorque = spec.ptoMotorSideTorque,
        ptoNativeCapacityTorque = spec.ptoNativeCapacityTorque,
        ptoEngagementCount = spec.ptoEngagementCount
    })
    spec.ptoEngagementPulseCount = 0
end

---Wears the cooling system on sustained high cooling, overheating, cold shock and an expired service
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateCoolingSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local spec_motorized = self.spec_motorized
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.cooling.name)
    local systemData = spec.systems.cooling
    local expiredServiceFactor = 0
    local C = RMS_Config.CORE.COOLING_FACTOR_DATA
    local highCoolingFactor, overheatFactor, coldShockFactor = 0, 0, 0
    local wearRate = 1.0
    local rpmLoad = 0

    if not systemData.enabled then
        return
    end

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() and not spec.isElectricVehicle then
        local lastRpm = spec_motorized.motor:getLastModulatedMotorRpm()
        local maxRpm = spec_motorized.motor.maxRpm
        rpmLoad = lastRpm / maxRpm

        -- high cooling, only once the circuit is saturated and losing the target
        if spec.engineTemperature > RMS_Config.THERMAL.PID_TARGET_TEMP + C.HIGH_COOLING_TEMP_MARGIN then
            if spec.thermostatState > C.HIGH_COOLING_FACTOR_THRESHOLD then
                highCoolingFactor = RMS_Utils.calculateQuadraticMultiplier(spec.thermostatState, C.HIGH_COOLING_FACTOR_THRESHOLD, false)
                highCoolingFactor = highCoolingFactor * (C.HIGH_COOLING_FACTOR_MULTIPLIER or 0)
                highCoolingFactor = math.min(highCoolingFactor, C.HIGH_COOLING_FACTOR_MULTIPLIER or highCoolingFactor)
                wearRate = wearRate + highCoolingFactor
            end
        end

        -- overheat
        if (spec.engineTemperature or -99) > C.OVERHEAT_FACTOR_THRESHOLD then
            overheatFactor = RMS_Utils.calculateQuadraticMultiplier(spec.engineTemperature, C.OVERHEAT_FACTOR_THRESHOLD, false, 120)
            overheatFactor = overheatFactor * (C.OVERHEAT_FACTOR_MULTIPLIER or 0)
            overheatFactor = math.min(overheatFactor, C.OVERHEAT_FACTOR_MULTIPLIER or overheatFactor)
            wearRate = wearRate + overheatFactor
        end

        -- cold shock
        if (spec.engineTemperature or -99) < C.COLD_SHOCK_FACTOR_THRESHOLD and rpmLoad > 0.75 then
            coldShockFactor = RMS_Utils.calculateQuadraticMultiplier(spec.engineTemperature, C.COLD_SHOCK_FACTOR_THRESHOLD, true)
            local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(rpmLoad, 0.75, false)
            coldShockFactor = coldShockFactor * (C.COLD_SHOCK_FACTOR_MULTIPLIER or 0) * motorLoadInf
            coldShockFactor = math.min(coldShockFactor, C.COLD_SHOCK_FACTOR_MULTIPLIER or coldShockFactor)
            wearRate = wearRate + coldShockFactor
        end

        -- idling
        if spec.thermostatState == 0 and overheatFactor == 0 and coldShockFactor == 0 then
            wearRate = wearRate * C.COOLING_IDLING_MULTIPLIER
        end

        -- service factor
        expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        if spec.isUnderRoof then 
            wearRate = wearRate * RMS_Config.CORE.UNDER_ROOF_DOWNTIME_MULTIPLIER 
        else
            wearRate = wearRate * RMS_Config.CORE.DOWNTIME_MULTIPLIER
        end
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        highCoolingFactor = highCoolingFactor,
        overheatFactor = overheatFactor,
        coldShockFactor = coldShockFactor,
        engineTemperature = spec.engineTemperature,
        rpmLoad = rpmLoad,
        thermostatState = spec.thermostatState
    })
end

---Wears the electrical system on cranking, weather exposure, lights, overheating, vibration and an expired service
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateElectricalSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.electrical.name)
    local systemData = spec.systems.electrical
    if systemData == nil then return end
    local vibState = spec.chassisVibState
    local vibSignal = vibState.signal
    local vibRaw = vibState.raw
    local vibFieldMultiplier = vibState.fieldMultiplier
    local expiredServiceFactor, weatherExposureFactor, lightsFactor, overheatFactor, crankingStressFactor, vibFactor = 0, 0, 0, 0, 0, 0
    local C = RMS_Config.CORE.ELECTRICAL_FACTOR_DATA
    local wearRate = 1.0

    if not systemData.enabled then
        return
    end

    local isOutdoor = not spec.isUnderRoof

    -- lights factor
    if self.spec_lights ~= nil and self.getLightsTypesMask ~= nil then
        local lightsSpec = self.spec_lights
        local lightsMask = tonumber(self:getLightsTypesMask()) or 0
        local maxLightStateMask = tonumber(lightsSpec.maxLightStateMask) or 0
        local activeMainLightsMask = lightsMask

        if maxLightStateMask > 0 and bitAND ~= nil then
            activeMainLightsMask = bitAND(lightsMask, maxLightStateMask)
        end

        if activeMainLightsMask > 0 then
            lightsFactor = C.LIGHTS_FACTOR_MULTIPLIER or 0
            wearRate = wearRate + lightsFactor
        end
    end

    -- weather factor
    if isOutdoor then
        local weatherType = RMS_Main.currentWeather
        if weatherType == WeatherType.RAIN then
            weatherExposureFactor = C.RAIN_FACTOR_MULTIPLIER or 0
        elseif weatherType == WeatherType.SNOW then
            weatherExposureFactor = C.SNOW_FACTOR_MULTIPLIER or 0
        elseif weatherType == WeatherType.HAIL then
            weatherExposureFactor = C.HAIL_FACTOR_MULTIPLIER or 0
        end
        wearRate = wearRate + weatherExposureFactor
    end

    -- cranking factor
    systemData.crankingTimer = systemData.crankingTimer or 0
    if not spec.isElectricVehicle and spec.isCranking then
        systemData.crankingTimer = math.min(systemData.crankingTimer + dt, 10000)
        if systemData.crankingTimer > 3500 then
            crankingStressFactor = C.CRANKING_STRESS_MULTIPLIER
            wearRate = wearRate + crankingStressFactor
        end
    else
        systemData.crankingTimer = math.max(systemData.crankingTimer - dt / 100, 0)
    end

    if self:getIsMotorStarted() and not spec.isElectricVehicle then
        -- service factor
        expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor

        -- overheating engine compartment
        if (spec.engineTemperature or -99) > C.OVERHEAT_FACTOR_THRESHOLD then
            overheatFactor = RMS_Utils.calculateQuadraticMultiplier(spec.engineTemperature, C.OVERHEAT_FACTOR_THRESHOLD, false, 120)
            overheatFactor = overheatFactor * (C.OVERHEAT_FACTOR_MULTIPLIER or 0)
            overheatFactor = math.min(overheatFactor, C.OVERHEAT_FACTOR_MULTIPLIER or overheatFactor)
            wearRate = wearRate + overheatFactor
        end

        -- vibration factor
        local vibThreshold = tonumber(C.VIB_FACTOR_THRESHOLD) or 0.12
        if vibState.smoothed > vibThreshold then
            local vibMaxSignal = tonumber(C.VIB_FACTOR_MAX_SIGNAL) or 0.22
            local vibMaxForCurve = math.max(vibMaxSignal, vibThreshold + 0.001)
            local vibMultiplier = (tonumber(C.VIB_FACTOR_MULTIPLIER) or 4.0) * vibFieldMultiplier
            vibFactor = RMS_Utils.calculateQuadraticMultiplier(vibState.smoothed, vibThreshold, false, vibMaxForCurve)
            vibFactor = vibFactor * vibMultiplier
            vibFactor = math.min(vibFactor, vibMultiplier)
            wearRate = wearRate + vibFactor
        end

    elseif lightsFactor == 0 and crankingStressFactor == 0 then 
        if spec.isUnderRoof then 
            wearRate = wearRate * RMS_Config.CORE.UNDER_ROOF_DOWNTIME_MULTIPLIER 
        else
            wearRate = wearRate * RMS_Config.CORE.DOWNTIME_MULTIPLIER 
        end
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        crankingStressFactor = crankingStressFactor,
        crankingTimer = systemData.crankingTimer or 0,
        weatherExposureFactor = weatherExposureFactor,
        lightsFactor = lightsFactor,
        overheatFactor = overheatFactor,
        engineTemperature = spec.engineTemperature,
        vibFactor = vibFactor,
        vibSignal = vibSignal,
        vibRaw = vibRaw,
        vibFieldMultiplier = vibFieldMultiplier
    })
end

---Wears the chassis on vibration, steering load, braking mass, lubrication and an expired service
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateChassisSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.chassis.name)
    local systemData = spec.systems.chassis
    local expiredServiceFactor, lubricationFactor, vibFactor, steerLoadFactor = 0, 0, 0, 0
    local vibState = spec.chassisVibState
    local steerState = spec.chassisSteerState
    local brakeState = spec.chassisBrakeState
    local vibSignal = vibState.signal
    local vibRaw = vibState.raw
    local vibWheelCount = vibState.wheelCount
    local vibSpeedFactor = vibState.speedFactor
    local vibAvgDensityType = vibState.avgDensityType
    local vibFieldMultiplier = vibState.fieldMultiplier
    local steerLowSpeedFactor = 0
    local steerGroundFrictionCoeff = math.max(tonumber(spec.avgTireGroundFrictionCoeff) or 0, 0)
    local steerGroundFrictionFactor = steerGroundFrictionCoeff ^ 2
    local steerGroundContact = steerState.groundContact
    local steerDeltaRate = steerState.deltaRate
    local steerAngleRatio = math.clamp(tonumber(steerState.angleRatio) or 0, 0, 1)
    local steerAxleLoadRatio = math.max(tonumber(steerState.axleLoadRatio) or 1, 0)
    local steerMoving = steerState.isMoving == true
    local brakeMassFactor = 0
    local isTruck = spec.isTruck == true
    local trailerMass = math.max(brakeState.trailerMass, 0)
    local hpBrakeMassRatio = isTruck
        and brakeState.hpGrossMassRatio
        or brakeState.hpTrailerMassRatio
    local brakePedal = brakeState.pedal
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local brakeMassRatioThreshold = isTruck
        and (tonumber(C.BRAKE_MASS_TRUCK_RATIO_THRESHOLD) or 6.0)
        or (tonumber(C.BRAKE_MASS_RATIO_THRESHOLD) or 10.0)
    local brakeMassFullEffectRatio = isTruck
        and (tonumber(C.BRAKE_MASS_TRUCK_RATIO_FULL_EFFECT) or 3.0)
        or (tonumber(C.BRAKE_MASS_RATIO_FULL_EFFECT) or 5.0)
    local wearRate = 1.0

    if not systemData.enabled then
        return
    end

    local speed = self:getLastSpeed()


    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        if spec.isVehicleNeedLubricate then
            local lubricationLevel = math.clamp(tonumber(spec.lubricationLevel) or 1.0, 0.0, 1.0)
            lubricationFactor = RMS_Utils.calculateQuadraticMultiplier(
                lubricationLevel,
                RMS_Config.FIELD_CARE.LUBRICATION_WARNING_THRESHOLD,
                true,
                0.0
            )
            lubricationFactor = lubricationFactor * (C.LUBRICATION_FACTOR_MULTIPLIER or 0)
            wearRate = wearRate + lubricationFactor
        end

        if speed > 0.003 then
            -- vibration
            local vibThreshold = tonumber(C.VIB_FACTOR_THRESHOLD) or 0.12
            if vibState.smoothed > vibThreshold then
                local vibMaxSignal = tonumber(C.VIB_FACTOR_MAX_SIGNAL) or 0.22
                local vibMaxForCurve = math.max(vibMaxSignal, vibThreshold + 0.001)
                local vibMultiplier = (tonumber(C.VIB_FACTOR_MULTIPLIER) or 4.0) * vibFieldMultiplier
                vibFactor = RMS_Utils.calculateQuadraticMultiplier(vibState.smoothed, vibThreshold, false, vibMaxForCurve)
                vibFactor = vibFactor * vibMultiplier
                vibFactor = math.min(vibFactor, vibMultiplier)
                wearRate = wearRate + vibFactor
            end

            -- braking under mass
            if trailerMass > 0.1 and brakeState.isBraking and speed > (tonumber(C.BRAKE_MASS_SPEED_THRESHOLD) or 2.0) then
                if hpBrakeMassRatio < brakeMassRatioThreshold then
                    local ratioFactor = RMS_Utils.calculateQuadraticMultiplier(hpBrakeMassRatio, brakeMassRatioThreshold, true, brakeMassFullEffectRatio)
                    local brakeInputFactor = brakePedal
                    brakeMassFactor = ratioFactor * brakeInputFactor * (tonumber(C.BRAKE_MASS_FACTOR_MULTIPLIER) or 6.0)
                    brakeMassFactor = math.min(brakeMassFactor, tonumber(C.BRAKE_MASS_FACTOR_MULTIPLIER) or brakeMassFactor)
                    wearRate = wearRate + brakeMassFactor
                end
            end

        else
            wearRate = wearRate * C.CHASSIS_IDLING_MULTIPLIER    
        end

        -- steering load at standstill / low speed
        local steerSpeedThreshold = tonumber(C.STEER_LOAD_SPEED_THRESHOLD) or 4.0
        if steerSpeedThreshold > 0 and steerState.isLowSpeedActive and steerGroundContact > 0 and steerMoving then
            steerLowSpeedFactor = RMS_Utils.calculateQuadraticMultiplier(math.clamp(speed, 0, steerSpeedThreshold), steerSpeedThreshold, true)
            if steerLowSpeedFactor > 0 then
                steerLoadFactor = steerLowSpeedFactor * steerAngleRatio * steerAxleLoadRatio * (tonumber(C.STEER_LOAD_FACTOR_MULTIPLIER) or 5.0) * steerGroundFrictionFactor
                wearRate = wearRate + steerLoadFactor
            end
        end

        -- service
        if not spec.isElectricVehicle then
            expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER)
            wearRate = wearRate + expiredServiceFactor
        end
    else
        if spec.isUnderRoof then 
            wearRate = wearRate * RMS_Config.CORE.UNDER_ROOF_DOWNTIME_MULTIPLIER 
        else
            wearRate = wearRate * RMS_Config.CORE.DOWNTIME_MULTIPLIER 
        end
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        lubricationFactor = lubricationFactor,
        vibFactor = vibFactor,
        vibSignal = vibSignal,
        vibRaw = vibRaw,
        vibWheelCount = vibWheelCount,
        vibSpeedFactor = vibSpeedFactor,
        vibSpeedKmh = speed,
        vibAvgDensityType = vibAvgDensityType,
        vibFieldMultiplier = vibFieldMultiplier,
        steerLoadFactor = steerLoadFactor,
        steerLowSpeedFactor = steerLowSpeedFactor,
        steerGroundFrictionCoeff = steerGroundFrictionCoeff,
        steerGroundFrictionFactor = steerGroundFrictionFactor,
        steerDeltaRate = steerDeltaRate,
        steerAngleRatio = steerAngleRatio,
        steerAxleLoadRatio = steerAxleLoadRatio,
        steerGroundContact = steerGroundContact,
        steerMoving = steerMoving,
        brakeMassFactor = brakeMassFactor,
        brakeMassRatio = hpBrakeMassRatio,
        brakeMassBasis = isTruck and "gcw" or "trailer",
        brakePedal = brakePedal
    })
end

---Wears the fuel system on low fuel starvation, cold fuel, idle deposits, high pressure and an expired service
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateFuelSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.fuel.name)
    local systemData = spec.systems.fuel
    if systemData == nil then return end
    local lowFuelStarvationFactor, coldFuelFactor = 0, 0
    local expiredServiceFactor, fuelLevel, fuelTemperature, idleDepositFactor, highPressureFactor = 0, 0, 0, 0, 0
    local currentFuelUsageRatio = 0
    local C = RMS_Config.CORE.FUEL_FACTOR_DATA
    local wearRate = 1.0
    local fuelState = spec.fuelState

    if not systemData.enabled then
        return
    end

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() and not spec.isElectricVehicle then
        local motorLoad = self:getMotorLoadPercentage()
        fuelLevel = fuelState.level
        currentFuelUsageRatio = fuelState.currentUsageRatio

        -- low fuel
        if fuelLevel < C.LOW_FUEL_THRESHOLD then
            lowFuelStarvationFactor = RMS_Utils.calculateQuadraticMultiplier(fuelLevel, C.LOW_FUEL_THRESHOLD, true)
            local motorLoadInf = 1 + RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.70, false)
            lowFuelStarvationFactor = lowFuelStarvationFactor * motorLoadInf * C.LOW_FUEL_FACTOR_MULTIPLIER
            wearRate = wearRate + lowFuelStarvationFactor
        end

        -- cold fuel factor
        fuelTemperature = fuelState.temperature
        if fuelTemperature < C.COLD_FUEL_THRESHOLD and motorLoad > 0.5 then
            coldFuelFactor = RMS_Utils.calculateQuadraticMultiplier(fuelTemperature, C.COLD_FUEL_THRESHOLD, true)
            local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.50, false)
            coldFuelFactor = coldFuelFactor * motorLoadInf * C.COLD_FUEL_FACTOR_MULTIPLIER
            coldFuelFactor = math.min(coldFuelFactor, C.COLD_FUEL_FACTOR_MULTIPLIER or coldFuelFactor)
            wearRate = wearRate + coldFuelFactor
        end

        -- idle deposit
        local idleTimer = math.max(tonumber(fuelState.idleTimer) or 0, 0)
        if idleTimer >= C.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD then
            idleDepositFactor = RMS_Utils.calculateQuadraticMultiplier(
                idleTimer,
                C.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD,
                false,
                C.IDLE_DEPOSIT_FACTOR_MAX_TIMER
            )
            idleDepositFactor = idleDepositFactor * C.IDLE_DEPOSIT_FACTOR_MULTIPLIER
            wearRate = wearRate + idleDepositFactor
        end

        -- high pressure factor
        local highPressureThreshold = tonumber(C.HIGH_PRESSURE_FACTOR_THRESHOLD) or 0.8
        if currentFuelUsageRatio > highPressureThreshold then
            highPressureFactor = RMS_Utils.calculateQuadraticMultiplier(currentFuelUsageRatio, highPressureThreshold, false)
            highPressureFactor = math.min(highPressureFactor * C.HIGH_PRESSURE_FACTOR_MULTIPLIER, C.HIGH_PRESSURE_FACTOR_MULTIPLIER)
            wearRate = wearRate + highPressureFactor
        end

        -- service
        expiredServiceFactor = getExpiredServiceFactor(spec.serviceLevel, C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        if spec.isUnderRoof then 
            wearRate = wearRate * RMS_Config.CORE.UNDER_ROOF_DOWNTIME_MULTIPLIER 
        else
            wearRate = wearRate * RMS_Config.CORE.DOWNTIME_MULTIPLIER
        end
    end

    self:updateSystemConditionAndStress(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        lowFuelStarvationFactor = lowFuelStarvationFactor,
        coldFuelFactor = coldFuelFactor,
        idleDepositFactor = idleDepositFactor,
        highPressureFactor = highPressureFactor,
        currentFuelUsageRatio = currentFuelUsageRatio,
        idleTimer = fuelState.idleTimer,
        fuelLevel = fuelLevel,
        fuelTemperature = fuelTemperature
    })
end
