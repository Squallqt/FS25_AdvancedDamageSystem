-- ==========================================================
--                        AI WORKER
-- ==========================================================

local function getIsSoilSamplingActive(vehicle)
    local visited = {}

    local function visit(object)
        if object == nil or visited[object] then
            return false
        end
        visited[object] = true

        local soilSamplerSpec = object["spec_FS25_precisionFarming.soilSampler"]
        if soilSamplerSpec ~= nil and soilSamplerSpec.isSampling then
            return true
        end

        local attacherJoints = object.spec_attacherJoints
        local attachedImplements = attacherJoints ~= nil and attacherJoints.attachedImplements or nil
        if attachedImplements ~= nil then
            for _, implementData in pairs(attachedImplements) do
                if visit(implementData.object) then
                    return true
                end
            end
        end

        return false
    end

    return visit(vehicle)
end

function AdvancedDamageSystem:resetAiWorkerCruiseControlState(restoreCruiseSpeed)
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then return end

    local state = spec.aiWorkerPid
    if state == nil then return end

    if restoreCruiseSpeed ~= false and state.baseCruiseSpeed ~= nil and state.baseCruiseSpeed > 0 then
        local motor = self:getMotor()
        self:setCruiseControlMaxSpeed(motor:getMaximumForwardSpeed() * 3.6, nil)
    end

    state.integral = 0
    state.lastError = 0
    state.filteredStress = 0
    state.currentReduction = 0
    state.baseCruiseSpeed = nil
    state.applyTimer = 0
    state.lastAppliedSpeed = nil

    if ADS_Config.DEBUG and spec.debugData and spec.debugData.aiWorker then
        local dbg = spec.debugData.aiWorker
        dbg.stress = 0
        dbg.filteredStress = 0
        dbg.error = 0
        dbg.integral = 0
        dbg.derivative = 0
        dbg.reduction = 0
        dbg.targetSpeed = 0
        dbg.appliedSpeed = 0
        dbg.baseCruiseSpeed = 0
        dbg.loadStress = 0
        dbg.engineStress = 0
        dbg.transStress = 0
    end
end

function AdvancedDamageSystem:getAiWorkerImplementSpeedLimit()
    local speedLimit = math.huge

    if self.spec_attacherJoints and self.spec_attacherJoints.attachedImplements and next(self.spec_attacherJoints.attachedImplements) ~= nil then
        for _, implementData in pairs(self.spec_attacherJoints.attachedImplements) do
            if implementData.object ~= nil then
                local implement = implementData.object
                local currentSpeedLimit = implement.speedLimit
                if currentSpeedLimit ~= nil and implement.getIsLowered ~= nil and implement:getIsLowered() then
                    speedLimit = math.min(speedLimit, currentSpeedLimit)
                end
            end
        end
    end

    return speedLimit
end

function AdvancedDamageSystem:updateAiWorkerCruiseControl(dt)
    if not self.isServer then return end
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then return end

    if self.propertyState == 4 and not ADS_Config.CORE.CONTRACT_VEHICLE_PROTECTION then
        self:resetAiWorkerCruiseControlState()
        return
    end

    local config = ADS_Config.CORE and ADS_Config.CORE.AI_WORKER_PID
    if config == nil then return end

    if spec.aiWorkerPid == nil then
        spec.aiWorkerPid = {
            integral = 0,
            lastError = 0,
            filteredStress = 0,
            currentReduction = 0,
            baseCruiseSpeed = nil,
            applyTimer = 0,
            lastAppliedSpeed = nil
        }
    end

    if not self:getIsAIActive() or not self:getIsMotorStarted() then
        self:resetAiWorkerCruiseControlState()
        return
    end

    if getIsSoilSamplingActive(self) then
        self:resetAiWorkerCruiseControlState(false)
        return
    end

    local cruiseSpeed = self:getCruiseControlSpeed() or 0
    if cruiseSpeed <= 0 then
        self:resetAiWorkerCruiseControlState()
        return
    end

    local state = spec.aiWorkerPid
    local dtMs = math.max(dt or ADS_Config.ON_UPDATE_DELAY, 1)
    local dtSeconds = math.max(dtMs / 1000, 0.05)

    local function normalizeToUnit(value, startValue, fullValue)
        local denominator = math.max(fullValue - startValue, 0.0001)
        return math.clamp((value - startValue) / denominator, 0.0, 1.0)
    end

    local motorLoad = math.max(spec.dynamicMotorLoad or self:getMotorLoadPercentage() or 0, 0)
    local rawEngineTemperature = AdvancedDamageSystem.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, 20, -80, 160)
    local rawTransmissionTemperature = AdvancedDamageSystem.sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, -99, -99, 180)
    if rawTransmissionTemperature < 0 then
        rawTransmissionTemperature = rawEngineTemperature
    end

    local loadStress = normalizeToUnit(motorLoad, config.LOAD_START, config.LOAD_FULL)
    local engineStress = normalizeToUnit(rawEngineTemperature, config.ENGINE_TEMP_START, config.ENGINE_TEMP_FULL)
    local transStress = normalizeToUnit(rawTransmissionTemperature, config.TRANS_TEMP_START, config.TRANS_TEMP_FULL)

    local stress = loadStress * config.WEIGHT_LOAD + engineStress * config.WEIGHT_ENGINE_TEMP + transStress * config.WEIGHT_TRANS_TEMP
    stress = math.clamp(stress, 0.0, 1.0)

    local filterTau = math.max(config.FILTER_TAU or 0.7, 0.05)
    local filterAlpha = dtSeconds / (filterTau + dtSeconds)
    state.filteredStress = state.filteredStress + (stress - state.filteredStress) * filterAlpha

    local error = state.filteredStress - config.TARGET_STRESS
    if math.abs(error) < config.DEADBAND then
        error = 0
    end

    local lastError = state.lastError or 0
    local derivative = (error - lastError) / math.max(dtSeconds, 0.001)

    local maxReduction = math.max(config.MAX_REDUCTION or 16, 0)
    local maxIntegral = math.max(config.MAX_INTEGRAL or 3, 0.001)

    local integrate = true
    if (state.currentReduction <= 0 and error < 0) or (state.currentReduction >= maxReduction and error > 0) then
        integrate = false
    end
    if integrate then
        state.integral = math.clamp((state.integral or 0) + error * dtSeconds, -maxIntegral, maxIntegral)
    end

    local rateCommand = config.KP * error + config.KI * state.integral + config.KD * derivative
    local reductionRate = math.max(config.REDUCTION_RATE_DOWN or 8.0, 0.1)
    local recoveryRate = math.max(config.RECOVERY_RATE_UP or 2.5, 0.1)
    rateCommand = math.clamp(rateCommand, -recoveryRate, reductionRate)
    state.currentReduction = math.clamp(state.currentReduction + rateCommand * dtSeconds, 0, maxReduction)

    local emergency = rawEngineTemperature >= (config.EMERGENCY_ENGINE_TEMP or 112) or rawTransmissionTemperature >= (config.EMERGENCY_TRANS_TEMP or 112)
    if emergency then
        state.currentReduction = maxReduction
        state.integral = math.max(state.integral, 0)
    end

    local minSpeed = math.max(config.MIN_SPEED or 5.0, 0)
    local estimatedBaseCruiseSpeed = math.max(cruiseSpeed + state.currentReduction, minSpeed)
    if state.baseCruiseSpeed == nil then
        state.baseCruiseSpeed = estimatedBaseCruiseSpeed
    end

    if estimatedBaseCruiseSpeed > state.baseCruiseSpeed then
        state.baseCruiseSpeed = estimatedBaseCruiseSpeed
    elseif state.currentReduction < 0.25 then
        local syncDownRate = math.max(config.BASE_SYNC_DOWN_RATE or 1.8, 0.1)
        local syncBlend = math.min(dtSeconds * syncDownRate, 1.0)
        state.baseCruiseSpeed = state.baseCruiseSpeed + (estimatedBaseCruiseSpeed - state.baseCruiseSpeed) * syncBlend
    end

    local baseSpeedLimit = state.baseCruiseSpeed
    local implementSpeedLimit = self:getAiWorkerImplementSpeedLimit()
    if implementSpeedLimit ~= math.huge then
        baseSpeedLimit = math.min(baseSpeedLimit, implementSpeedLimit)
    end

    local targetSpeed = math.max(minSpeed, baseSpeedLimit - state.currentReduction)
    local maxUpStep = recoveryRate * dtSeconds
    local maxDownStep = reductionRate * dtSeconds
    if targetSpeed > cruiseSpeed then
        targetSpeed = math.min(targetSpeed, cruiseSpeed + maxUpStep)
    elseif targetSpeed < cruiseSpeed then
        targetSpeed = math.max(targetSpeed, cruiseSpeed - maxDownStep)
    end
    targetSpeed = math.floor(targetSpeed * 10 + 0.5) / 10

    state.applyTimer = (state.applyTimer or 0) + dtMs
    local applyInterval = math.max(config.APPLY_INTERVAL_MS or 180, 50)
    local minApplyDelta = math.max(config.MIN_APPLY_DELTA or 0.2, 0.01)

    local shouldApply = emergency
    if not shouldApply and state.applyTimer >= applyInterval then
        local lastAppliedSpeed = state.lastAppliedSpeed or cruiseSpeed
        if math.abs(targetSpeed - lastAppliedSpeed) >= minApplyDelta or math.abs(targetSpeed - cruiseSpeed) >= minApplyDelta then
            shouldApply = true
        end
    end

    if shouldApply then
        self:setCruiseControlMaxSpeed(targetSpeed, nil)
        state.lastAppliedSpeed = targetSpeed
        state.applyTimer = 0
    end

    state.lastError = error

    if ADS_Config.DEBUG and spec.debugData and spec.debugData.aiWorker then
        local dbg = spec.debugData.aiWorker
        dbg.stress = stress
        dbg.filteredStress = state.filteredStress
        dbg.error = error
        dbg.integral = state.integral
        dbg.derivative = derivative
        dbg.reduction = state.currentReduction
        dbg.targetSpeed = targetSpeed
        dbg.appliedSpeed = state.lastAppliedSpeed or cruiseSpeed
        dbg.baseCruiseSpeed = state.baseCruiseSpeed or 0
        dbg.loadStress = loadStress
        dbg.engineStress = engineStress
        dbg.transStress = transStress
    end
end
