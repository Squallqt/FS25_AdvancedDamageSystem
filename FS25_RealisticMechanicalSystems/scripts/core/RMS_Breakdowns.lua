RMS_Breakdowns = {}

local log_dbg = RMS_Utils.createLogger("[RMS_BREAKDOWNS]")

local loggedHookErrors = {}

-- Speed in km/h below which a braking vehicle emits its brake sound, once per crossing.
local BRAKE_SOUND_SPEED_THRESHOLD = 15

-- Reports a wrapped engine call failure once per distinct error, regardless of debug mode.
local function log_hook_error(context, err)
    local key = context .. "|" .. tostring(err)
    if loggedHookErrors[key] then
        return
    end
    loggedHookErrors[key] = true
    Logging.error("[RMS_BREAKDOWNS] %s failed: %s", context, tostring(err))
end

source(g_currentModDirectory .. "scripts/core/RMS_BreakdownRegistry.lua")

-- ==========================================================
--                     BREAKDOWN EFFECTS
-- ==========================================================

RMS_Breakdowns.EffectApplicators = {}

local function addFuncToActive(v, effectName, func)
    if v.spec_RealisticMechanicalSystems.activeFunctions[effectName] == nil then
        v.spec_RealisticMechanicalSystems.activeFunctions[effectName] = func
    end
end

local function removeFuncFromActive(v, effectName)
    if v.spec_RealisticMechanicalSystems.activeFunctions[effectName] ~= nil then
        v.spec_RealisticMechanicalSystems.activeFunctions[effectName] = nil
    end
end

local function getStarterCrankingPitchOffset(preCrankVoltageV)
    local resolvedVoltage = preCrankVoltageV or 12.2
    local t = math.clamp((12.2 - resolvedVoltage) / 0.5, 0, 1)
    return -0.25 * (t * t)
end

local function getActiveStarterCrankingEffect(spec)
    if spec == nil or spec.activeEffects == nil then
        return nil
    end

    local engineFailure = spec.activeEffects.ENGINE_FAILURE
    if engineFailure ~= nil and engineFailure.extraData ~= nil and engineFailure.extraData.status == "CRANKING" then
        return engineFailure
    end

    local engineHardStart = spec.activeEffects.ENGINE_HARD_START_MODIFIER
    if engineHardStart ~= nil and engineHardStart.extraData ~= nil and engineHardStart.extraData.status == "CRANKING" then
        return engineHardStart
    end

    local glowPlugHardStart = spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER
    if glowPlugHardStart ~= nil and glowPlugHardStart.extraData ~= nil and glowPlugHardStart.extraData.status == "CRANKING" then
        return glowPlugHardStart
    end

    return nil
end

local function getIsStarterRequestActive(vehicle, effect)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and (spec.startButtonHeld == true
        or (effect ~= nil and effect.extraData ~= nil and effect.extraData.automaticCrank == true))
end

local function syncStarterCrankingSample(vehicle)
    if vehicle == nil or not vehicle.isClient then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local starterCrankingSample = spec ~= nil and spec.samples ~= nil and spec.samples.starterCranking or nil
    if starterCrankingSample == nil then
        return
    end

    local activeEffect = getActiveStarterCrankingEffect(spec)
    local startRequestActive = getIsStarterRequestActive(vehicle, activeEffect)
    local shouldPlay = activeEffect ~= nil and startRequestActive and not vehicle:getIsMotorStarted()

    if shouldPlay then
        local pitchOffset = getStarterCrankingPitchOffset(activeEffect.extraData.preCrankVoltageV)
        RMS_SoundManager.setSamplePitchOffset(starterCrankingSample, pitchOffset)
        RMS_SoundManager.setSamplePlaying(starterCrankingSample, true)
    else
        RMS_SoundManager.setSamplePlaying(starterCrankingSample, false, 0, 0)
        RMS_SoundManager.setSamplePitchOffset(starterCrankingSample, 0)
    end
end

local function playStarterCrankingEndSample(spec, pitchOffset)
    local starterCrankingEndSample = spec ~= nil and spec.samples ~= nil and spec.samples.starterCrankingEnd or nil
    if starterCrankingEndSample == nil then
        return
    end

    RMS_SoundManager.setSampleVolumeOffset(starterCrankingEndSample, 0)
    if not RMS_SoundManager.getIsSamplePlaying(starterCrankingEndSample) then
        RMS_SoundManager.setSamplePitchOffset(starterCrankingEndSample, pitchOffset or 0)
        RMS_SoundManager.playSample(starterCrankingEndSample)
    end
end

-- ==========================================================
-- SELF_DISAPPEARING_BREAKDOWN_EFFECT
RMS_Breakdowns.EffectApplicators.SELF_DISAPPEARING_BREAKDOWN_EFFECT = {
    apply = function(vehicle, effectData, handler)
        vehicle:removeBreakdown(effectData.extraData.breakdownId)
    end,

}

-- ==========================================================
-- ENGINE_FAILURE
RMS_Breakdowns.EffectApplicators.ENGINE_FAILURE = {
    getEffectName = function()
        return "ENGINE_FAILURE"
    end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local spec = vehicle.spec_RealisticMechanicalSystems
        local activeFunc = function(v, dt)
            local currentEffect = v.spec_RealisticMechanicalSystems.activeEffects ~= nil and v.spec_RealisticMechanicalSystems.activeEffects[effectName] or nil
            if currentEffect == nil or currentEffect.extraData == nil then
                return
            end

            if currentEffect.extraData.status ~= nil and currentEffect.extraData.status == 'CRANKING' then
                if currentEffect.extraData.preCrankVoltageV == nil then
                    currentEffect.extraData.preCrankVoltageV = spec.batteryTerminalVoltageV or spec.batteryOpenCircuitVoltageV or 12.2
                end
            end

            if v:getIsMotorStarted() then
                v:stopMotor()
            end
            if currentEffect.extraData.status ~= nil and currentEffect.extraData.status == 'CRANKING' then
                local startRequestActive = getIsStarterRequestActive(v, currentEffect)
                if not startRequestActive then
                    currentEffect.extraData.status = 'IDLE'
                    currentEffect.extraData.preCrankVoltageV = nil
                    currentEffect.extraData.automaticCrank = false
                    RMS_EffectSyncEvent.send(v, effectName, "IDLE", 0, 0, 0)
                end
            end

            syncStarterCrankingSample(v)
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        syncStarterCrankingSample(vehicle)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end,
}

-- ==========================================================
-- LIGHTS_FAILURE
RMS_Breakdowns.EffectApplicators.LIGHTS_FAILURE = {
    apply = function(vehicle, effectData, handler)
        local currentLightMask = vehicle:getLightsTypesMask()
        if currentLightMask ~= 0 then
            vehicle:setLightsTypesMask(0, true, true)
        end
    end,

}

function RMS_Breakdowns.setLightsTypesMask(self, superFunc, lightsTypesMask, force, noEventSend)
    local rootVehicle = self:getRootVehicle()
    local lightsFailure = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.LIGHTS_FAILURE
    if lightsFailure == nil then
        superFunc(self, lightsTypesMask, force, noEventSend)
    else
        local currentLightMask = self:getLightsTypesMask()
        if currentLightMask ~= 0 then 
            superFunc(self, 0, force, noEventSend)
        end  
        return
    end
end

-- ==========================================================
-- PTO_FAILURE
RMS_Breakdowns.EffectApplicators.PTO_FAILURE = {
    getEffectName = function() return "PTO_FAILURE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()

        local function forceDisablePtoConsumers(rootVehicle)
            local turnedOff = false
            local visited = {}

            local function walk(vehicleObj)
                if vehicleObj == nil or visited[vehicleObj] then
                    return
                end
                visited[vehicleObj] = true

                local ptoCapable = vehicleObj.getDoConsumePtoPower ~= nil
                    or vehicleObj.getIsPowerTakeOffActive ~= nil
                    or vehicleObj.getPtoRpm ~= nil

                local isTurnedOn = vehicleObj.getIsTurnedOn ~= nil and vehicleObj:getIsTurnedOn() or false
                if ptoCapable and isTurnedOn and vehicleObj.setIsTurnedOn ~= nil then
                    vehicleObj:setIsTurnedOn(false)
                    turnedOff = true
                end

                if vehicleObj.getAttachedImplements ~= nil then
                    local implements = vehicleObj:getAttachedImplements() or {}
                    for _, implement in pairs(implements) do
                        if implement ~= nil and implement.object ~= nil then
                            walk(implement.object)
                        end
                    end
                end
            end

            walk(rootVehicle)
            return turnedOff
        end

        local activeFunc = function(v, dt)
            local effect = v.spec_RealisticMechanicalSystems.activeEffects[effectName]
            if effect == nil or (tonumber(effect.value) or 0) <= 0 then
                return
            end
            effect.extraData = effect.extraData or {}
            forceDisablePtoConsumers(v)
        end

        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}
                 
-- ==========================================================
local function getWheelSeizureTargetWheel(vehicle)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    local spec_wheels = vehicle.spec_wheels
    if spec_rms == nil or spec_wheels == nil or spec_wheels.wheels == nil then
        return nil
    end

    local wheels = spec_wheels.wheels

    local function resolveWheelRuntime(wheel)
        local runtimeWheel = (wheel ~= nil and wheel.physics ~= nil) and wheel.physics or wheel
        if runtimeWheel == nil then
            return nil
        end

        local data = {
            wheel = wheel,
            runtime = runtimeWheel
        }

        data.node = runtimeWheel.node or (wheel and wheel.node) or nil
        data.wheelShape = runtimeWheel.wheelShape or (wheel and wheel.wheelShape) or nil
        data.wheelShapeCreated = (runtimeWheel.wheelShapeCreated == true) or (wheel and wheel.wheelShapeCreated == true) or false
        data.isLeft = runtimeWheel.isLeft
        if data.isLeft == nil and wheel ~= nil then
            data.isLeft = wheel.isLeft
        end
        data.brakeFactor = tonumber(runtimeWheel.brakeFactor) or tonumber(wheel and wheel.brakeFactor) or 0
        data.driveNode = runtimeWheel.driveNode or (wheel and wheel.driveNode) or data.node
        data.positionX = tonumber(runtimeWheel.positionX) or tonumber(wheel and wheel.positionX) or 0
        data.positionZ = tonumber(runtimeWheel.positionZ) or tonumber(wheel and wheel.positionZ) or 0
        data.steeringAngle = tonumber(runtimeWheel.steeringAngle) or tonumber(wheel and wheel.steeringAngle) or 0
        data.rotationDamping = tonumber(runtimeWheel.rotationDamping) or tonumber(wheel and wheel.rotationDamping) or 0
        data.torqueTarget = runtimeWheel

        return data
    end

    local function isValidWheelData(wd)
        return wd ~= nil
            and wd.node ~= nil and wd.node ~= 0
            and wd.wheelShape ~= nil and wd.wheelShape ~= 0
    end
    local cachedIndex = spec_rms.wheelSeizureTargetIndex
    if cachedIndex ~= nil then
        local cachedWheel = wheels[cachedIndex]
        local cachedData = resolveWheelRuntime(cachedWheel)
        if isValidWheelData(cachedData) then
            return cachedData
        end
    end

    local rootNode = vehicle.components and vehicle.components[1] and vehicle.components[1].node
    local function getWheelLocalPos(wheelData)
        if rootNode ~= nil and wheelData ~= nil then
            local sampleNode = wheelData.driveNode or wheelData.node
            if sampleNode ~= nil then
                local x, _, z = localToLocal(sampleNode, rootNode, 0, 0, 0)
                return x or 0, z or 0
            end
        end
        return wheelData and wheelData.positionX or 0, wheelData and wheelData.positionZ or 0
    end

    local function pickBest(predicate)
        local bestIndex = nil
        local bestZ = -math.huge
        for i, wheel in ipairs(wheels) do
            local wheelData = resolveWheelRuntime(wheel)
            if isValidWheelData(wheelData) and predicate(wheelData) then
                local _, z = getWheelLocalPos(wheelData)
                if bestIndex == nil or z > bestZ then
                    bestIndex = i
                    bestZ = z
                end
            end
        end
        return bestIndex
    end

    local bestIndex = pickBest(function(wheelData)
        local x = getWheelLocalPos(wheelData)
        return (wheelData.isLeft == false or x > 0) and wheelData.brakeFactor > 0
    end)

    if bestIndex == nil then
        bestIndex = pickBest(function(wheelData)
            local x = getWheelLocalPos(wheelData)
            return (wheelData.isLeft == false or x > 0)
        end)
    end

    if bestIndex == nil then
        bestIndex = pickBest(function(wheelData)
            return wheelData.brakeFactor > 0
        end)
    end

    if bestIndex == nil then
        bestIndex = pickBest(function(_)
            return true
        end)
    end

    spec_rms.wheelSeizureTargetIndex = bestIndex
    if bestIndex ~= nil then
        return resolveWheelRuntime(wheels[bestIndex])
    end
    return nil
end

-- ENGINE_LIMP_EFFECT
-- BRAKE_FORCE_MODIFIER
RMS_Breakdowns.EffectApplicators.BRAKE_FORCE_MODIFIER = {
}

-- STEERING_STATIC_BIAS_EFFECT
RMS_Breakdowns.EffectApplicators.STEERING_STATIC_BIAS_EFFECT = {
}

-- STEERING_SENSITIVITY_MODIFIER
RMS_Breakdowns.EffectApplicators.STEERING_SENSITIVITY_MODIFIER = {
}

-- WHEEL_SEIZURE_EFFECT
RMS_Breakdowns.EffectApplicators.WHEEL_SEIZURE_EFFECT = {
    remove = function(vehicle, handler)
        if vehicle.spec_RealisticMechanicalSystems ~= nil then
            vehicle.spec_RealisticMechanicalSystems.wheelSeizureTargetIndex = nil
        end
    end
}

-- ENGINE_HESITATION_CHANCE
RMS_Breakdowns.EffectApplicators.ENGINE_HESITATION_CHANCE = {
    getEffectName = function() return "ENGINE_HESITATION_CHANCE" end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)
            local extra = effectData.extraData

            if extra.status == "CHOKING" then
                extra.timer = extra.timer + dt
                if extra.timer > extra.duration then
                    if extra.cruiseState ~= 0 then
                        v:setCruiseControlState(extra.cruiseState, true)
                    end
                    extra.status = "IDLE"
                    extra.timer = 0
                end
            elseif v:getMotorLoadPercentage() > extra.motorLoad then
                if v.isServer and effectData.value > 0 and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effectData.value) and extra.status == "IDLE" then

                    local cruiseState = v:getCruiseControlState()
                    if cruiseState ~= 0 then
                        extra.cruiseState = cruiseState
                        v:setCruiseControlState(0, true)
                    end
                    extra.status = "CHOKING"
                    RMS_EffectSyncEvent.send(v, "ENGINE_HESITATION_CHANCE", "CHOKING", 0)

                end
            end
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

function RMS_Breakdowns.updateVehiclePhysics(vehicle, superFunc, axisForward, axisSide, doHandbrake, dt)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms == nil then
        return superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)
    end

    -- Parking brake: anchor the machine and ignore throttle, like a real park position.
    if RMS_Drivetrain.getIsParkBrakeEngaged(vehicle) then
        if vehicle:getCruiseControlState() ~= Drivable.CRUISECONTROL_STATE_OFF then
            vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
        end
        axisForward = 0
        doHandbrake = true
    end

    local brakeEffect = spec_rms and spec_rms.activeEffects.BRAKE_FORCE_MODIFIER
    local limpEffect = spec_rms and spec_rms.activeEffects.ENGINE_LIMP_EFFECT
    local hesitationEffect = spec_rms and spec_rms.activeEffects.ENGINE_HESITATION_CHANCE
    local steeringStaticBiasEffect = spec_rms and spec_rms.activeEffects.STEERING_STATIC_BIAS_EFFECT
    local steeringSensitivityEffect = spec_rms and spec_rms.activeEffects.STEERING_SENSITIVITY_MODIFIER
    local wheelSeizureEffect = spec_rms and spec_rms.activeEffects.WHEEL_SEIZURE_EFFECT
    local isBraking = false
    local drivingMode = vehicle:getDirectionChangeMode()

    if hesitationEffect and hesitationEffect.extraData and hesitationEffect.extraData.status == "CHOKING" then
        axisForward = axisForward * math.max(1 - hesitationEffect.extraData.amplitude, 0)
    end

    -- Steering sensitivity modifier: reduces driver steering input effect.
    if steeringSensitivityEffect ~= nil and steeringSensitivityEffect.value ~= nil then
        local value = math.max(tonumber(steeringSensitivityEffect.value) or 0, 0)
        local sensitivity = math.clamp(1 - value, 0.05, 1.0)
        axisSide = axisSide * sensitivity
    end

    -- Static steering bias: always drifts left, value controls offset angle/intensity.
    if steeringStaticBiasEffect ~= nil and steeringStaticBiasEffect.value ~= nil then
        local value = math.abs(tonumber(steeringStaticBiasEffect.value) or 0)
        local leftBias = -math.clamp(value, 0, 1.0)
        local x = math.clamp(axisSide, -1.0, 1.0)

        -- Keep full steering range while shifting neutral point to the left.
        -- Endpoints remain: f(-1) = -1, f(1) = 1, with f(0) = leftBias.
        if x < 0 then
            axisSide = (1 + leftBias) * x + leftBias
        else
            axisSide = (1 - leftBias) * x + leftBias
        end
        axisSide = math.clamp(axisSide, -1.0, 1.0)
    end

    if limpEffect and limpEffect.value then
        local maxAllowedAcceleration = math.max(1 + limpEffect.value, 0.2)
        if math.abs(axisForward) > maxAllowedAcceleration then
            if drivingMode == 2 then
                if axisForward > maxAllowedAcceleration then
                    axisForward = maxAllowedAcceleration
                end
            else
                if math.sign(vehicle.movingDirection) == math.sign(axisForward) then
                    if axisForward > 0 then
                        axisForward = maxAllowedAcceleration
                    else
                        axisForward = -1 * maxAllowedAcceleration
                    end
                end
            end
        end
    end

    if brakeEffect and brakeEffect.value ~= 0 then
        if drivingMode == 2 then
            isBraking = axisForward < -0.01
        else
            isBraking = vehicle.movingDirection ~= 0 and axisForward ~= 0 and math.sign(vehicle.movingDirection) ~= math.sign(axisForward)
        end
        
        if isBraking then
            local modifier = math.max(0.01, 1 + brakeEffect.value) 
            local origAxisForward = axisForward
            axisForward = axisForward * modifier
            if vehicle.isServer and brakeEffect.extraData ~= nil then
                local speed = vehicle:getLastSpeed()
                local previousSpeed = brakeEffect.extraData.previousSpeed or speed
                brakeEffect.extraData.previousSpeed = speed

                if previousSpeed >= BRAKE_SOUND_SPEED_THRESHOLD and speed < BRAKE_SOUND_SPEED_THRESHOLD
                    and math.abs(origAxisForward) > 0.999
                    and math.random() < math.abs(brakeEffect.value) then
                    local sampleIndex = math.random(3)
                    RMS_SoundManager.playSample(spec_rms.samples["brakes" .. sampleIndex])
                    RMS_EffectSyncEvent.send(vehicle, "BRAKE_FORCE_MODIFIER", "SOUND", 0, sampleIndex)
                end
            end
        end
    end

    local result = superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)

    if wheelSeizureEffect ~= nil and (tonumber(wheelSeizureEffect.value) or 0) > 0 and vehicle.isAddedToPhysics then
        local wheelData = getWheelSeizureTargetWheel(vehicle)
        if wheelData ~= nil and wheelData.node ~= nil and wheelData.node ~= 0 and wheelData.wheelShape ~= nil and wheelData.wheelShape ~= 0 then
            local intensity = math.clamp(tonumber(wheelSeizureEffect.value) or 1.0, 0, 1.0)
            local baseBrakeForce = 0
            if vehicle.getBrakeForce ~= nil then
                baseBrakeForce = tonumber(vehicle:getBrakeForce()) or 0
            end
            if baseBrakeForce <= 0 and vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor ~= nil and vehicle.spec_motorized.motor.getBrakeForce ~= nil then
                baseBrakeForce = tonumber(vehicle.spec_motorized.motor:getBrakeForce()) or 0
            end
            baseBrakeForce = math.max(baseBrakeForce, 100)

            -- Seized wheel: heavy drag without fully anchoring vehicle in place.
            local lockBrakeForce = math.max(baseBrakeForce * intensity, 100)
            local lockDamping = math.max((tonumber(wheelData.rotationDamping) or 0) * (3 + 4 * intensity), 5)

            if wheelData.torqueTarget ~= nil then
                wheelData.torqueTarget.torque = 0
            end
            if wheelData.wheel ~= nil and wheelData.wheel ~= wheelData.torqueTarget then
                wheelData.wheel.torque = 0
            end
            setWheelShapeProps(
                wheelData.node,
                wheelData.wheelShape,
                0,
                lockBrakeForce,
                wheelData.steeringAngle or 0,
                lockDamping
            )
        end
    end

    return result
end

-- ==========================================================
-- ENGINE_TORQUE_MODIFIER
RMS_Breakdowns.EffectApplicators.ENGINE_TORQUE_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        vehicle:updateMotorProperties()
    end,

    remove = function(vehicle, handler)
        vehicle:updateMotorProperties()
    end
}

if VehicleMotor ~= nil and VehicleMotor.getTorqueCurveValue ~= nil then
    VehicleMotor.getTorqueCurveValue = Utils.overwrittenFunction(VehicleMotor.getTorqueCurveValue, function(self, superFunc, rpm)
        local torque = superFunc(self, rpm)
        local vehicle = self.vehicle
        if vehicle ~= nil then
            local spec_rms = vehicle.spec_RealisticMechanicalSystems
            if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
                local effect = spec_rms.activeEffects.ENGINE_TORQUE_MODIFIER
                if effect ~= nil and effect.value ~= nil then
                    torque = torque * math.max((1 + effect.value), 0.2)
                end
            end
        end
        return torque
    end)
end
                  
-- ==========================================================
-- PTO_TORQUE_TRANSFER_MODIFIER
RMS_Breakdowns.EffectApplicators.PTO_TORQUE_TRANSFER_MODIFIER = {

}

if PowerConsumer ~= nil and PowerConsumer.getTotalConsumedPtoTorque ~= nil then
    local rmsPtoCallDepth = 0
    PowerConsumer.getTotalConsumedPtoTorque = Utils.overwrittenFunction(PowerConsumer.getTotalConsumedPtoTorque, function(self, superFunc, excludeVehicle, expected, ignoreTurnOnPeak)
        rmsPtoCallDepth = rmsPtoCallDepth + 1
        local callDepth = rmsPtoCallDepth

        local ok, torque, virtualMultiplicator = pcall(superFunc, self, excludeVehicle, expected, ignoreTurnOnPeak)
        if not ok then
            rmsPtoCallDepth = math.max(rmsPtoCallDepth - 1, 0)
            log_hook_error("PowerConsumer.getTotalConsumedPtoTorque", torque)
            return 0, 1
        end

        if callDepth == 1 then
            local rootVehicle = self
            if rootVehicle ~= nil and rootVehicle.getRootVehicle ~= nil then
                rootVehicle = rootVehicle:getRootVehicle()
            end

            local spec = rootVehicle ~= nil and rootVehicle.spec_RealisticMechanicalSystems or nil
            local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.PTO_TORQUE_TRANSFER_MODIFIER or nil
            if effect ~= nil then
                local effectValue = tonumber(effect.value) or 0
                local transferScale = math.max(0, 1 + effectValue)
                local modifiedTorque = torque * transferScale

                torque = modifiedTorque
            end
        end

        rmsPtoCallDepth = math.max(rmsPtoCallDepth - 1, 0)
        return torque, virtualMultiplicator
    end)
end
                  
-- ==========================================================
-- FUEL_CONSUMPTION_MODIFIER
RMS_Breakdowns.EffectApplicators.FUEL_CONSUMPTION_MODIFIER = {
}

function RMS_Breakdowns.updateConsumers(vehicle, dt, accInput)
	local spec = vehicle.spec_motorized
	local idleFactor = 0.5
	local rpmPercentage = (spec.motor.lastMotorRpm - spec.motor.minRpm) / (spec.motor.maxRpm - spec.motor.minRpm)
	local rpmFactor = idleFactor + rpmPercentage * (1 - idleFactor)
	local loadFactor = math.max(spec.smoothedLoadPercentage * rpmPercentage, 0)
	local motorFactor = 0.5 * (0.2 * rpmFactor + 1.8 * loadFactor)
    local timeScale = 1

    if g_modIsLoaded ~= nil and g_modIsLoaded["FS25_ingameTimeOperatingHours"] then
        local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
        timeScale = (missionInfo and missionInfo.timeScale) or 1
        if timeScale <= 0 then
            timeScale = 1
        end
    end

    local fuelUsageFactors = {
        [1] = 1.0,
        [2] = 1.5,
        [3] = 2.5
    }
    
    local fuelSetting = g_currentMission.missionInfo.fuelUsage
    
    local usageFactor = fuelUsageFactors[fuelSetting] or 1.5

	local damage = vehicle:getVehicleDamage()

	if damage > 0 then
		usageFactor = usageFactor * (1 + damage * Motorized.DAMAGED_USAGE_INCREASE)
	end

    if vehicle.spec_RealisticMechanicalSystems ~= nil then
        local fuelEffect = vehicle.spec_RealisticMechanicalSystems.activeEffects.FUEL_CONSUMPTION_MODIFIER
        local rmsFuelModifier = (fuelEffect and fuelEffect.value) or 0
        usageFactor = usageFactor * (1 + rmsFuelModifier)
    end

	for _, consumer in pairs(spec.consumers) do
		if consumer.permanentConsumption and consumer.usage > 0 then
			local used = usageFactor * motorFactor * consumer.usage * dt * timeScale

			if used ~= 0 then
				consumer.fillLevelToChange = consumer.fillLevelToChange + used

				if math.abs(consumer.fillLevelToChange) > 1 then
					used = consumer.fillLevelToChange
					consumer.fillLevelToChange = 0
					local fillType = vehicle:getFillUnitLastValidFillType(consumer.fillUnitIndex)
					local stats = g_currentMission:farmStats(vehicle:getOwnerFarmId())

					stats:updateStats("fuelUsage", used)

					if vehicle:getIsAIActive() and (fillType == FillType.DIESEL or fillType == FillType.DEF) and g_currentMission.missionInfo.helperBuyFuel then
						if fillType == FillType.DIESEL then
							local price = used * g_currentMission.economyManager:getCostPerLiter(fillType) * 1.5

							stats:updateStats("expenses", price)
							g_currentMission:addMoney(-price, vehicle:getOwnerFarmId(), MoneyType.PURCHASE_FUEL, true)
						end

						used = 0
					end

					if fillType == consumer.fillType then
						vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), consumer.fillUnitIndex, -used, fillType, ToolType.UNDEFINED)
					end
				end

				local usage = used / dt * 1000 * 60 * 60
                if timeScale ~= 0 then
                    usage = usage / timeScale
                end

				if consumer.fillType == FillType.DIESEL or consumer.fillType == FillType.ELECTRICCHARGE or consumer.fillType == FillType.METHANE then
					spec.lastFuelUsage = usage
				elseif consumer.fillType == FillType.DEF then
					spec.lastDefUsage = usage
				end
			end
		end
	end

	if spec.consumersByFillTypeName.AIR ~= nil then
		local consumer = spec.consumersByFillTypeName.AIR
		local fillType = vehicle:getFillUnitLastValidFillType(consumer.fillUnitIndex)

		if fillType == consumer.fillType then
			local usage = 0
			local direction = vehicle.movingDirection * vehicle:getReverserDirection()
			local forwardBrake = direction > 0 and accInput < 0
			local backwardBrake = direction < 0 and accInput > 0
			local brakeIsPressed = vehicle:getLastSpeed() > 1 and (forwardBrake or backwardBrake)

			if brakeIsPressed then
				local delta = math.abs(accInput) * dt * vehicle:getAirConsumerUsage() / 1000

				vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), consumer.fillUnitIndex, -delta, consumer.fillType, ToolType.UNDEFINED)

				usage = delta / dt * 1000
			end

			local fillLevelPercentage = vehicle:getFillUnitFillLevelPercentage(consumer.fillUnitIndex)

			if fillLevelPercentage < consumer.refillCapacityPercentage then
				consumer.doRefill = true
			elseif fillLevelPercentage == 1 then
				consumer.doRefill = false
			end

			if consumer.doRefill then
				local delta = consumer.refillLitersPerSecond / 1000 * dt

				vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), consumer.fillUnitIndex, delta, consumer.fillType, ToolType.UNDEFINED)

				usage = -delta / dt * 1000
			end

			spec.lastAirUsage = usage
		end
	end
end

function RMS_Breakdowns.updateConsumersOverwrite(vehicle, superFunc, dt, accInput)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
        local effect = spec_rms.activeEffects.FUEL_CONSUMPTION_MODIFIER
        if effect ~= nil and effect.value ~= nil then
            return RMS_Breakdowns.updateConsumers(vehicle, dt, accInput)
        end
    end
    return superFunc(vehicle, dt, accInput)
end

-- ==========================================================
-- TRANSMISSION_SLIP_EFFECT
RMS_Breakdowns.EffectApplicators.TRANSMISSION_SLIP_EFFECT = {
    apply = function(vehicle, effectData, handler)
        local motor = vehicle:getMotor()
        if motor == nil then return end

        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms._origClutchSlippingTime == nil then
            spec_rms._origClutchSlippingTime = motor.clutchSlippingTime
        end
        motor.clutchSlippingTime = spec_rms._origClutchSlippingTime * (1 + effectData.value) ^ 3
    end,

    remove = function(vehicle, handler)
        local motor = vehicle:getMotor()
        if motor == nil then return end

        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms._origClutchSlippingTime ~= nil then
            motor.clutchSlippingTime = spec_rms._origClutchSlippingTime
            spec_rms._origClutchSlippingTime = nil
        end
    end
}

-- CVT_SLIP_EFFECT
RMS_Breakdowns.EffectApplicators.CVT_SLIP_EFFECT = {

    remove = function(vehicle, handler)
        local motor = vehicle:getMotor()
        if motor ~= nil then
            motor:setExternalTorqueVirtualMultiplicator(1)
        end
    end
}

-- CVT_MAX_RATIO_MODIFIER
RMS_Breakdowns.EffectApplicators.CVT_MAX_RATIO_MODIFIER = {
}

-- Convergence rate of the transmission slip modifier, per second at full factor.
local TRANSMISSION_SLIP_CONVERGENCE_PER_SECOND = 0.9
-- Gap beyond which a frame contributes no elapsed time.
local TRANSMISSION_SLIP_RESUME_GAP_SECONDS = 0.25

if VehicleMotor ~= nil and VehicleMotor.getMinMaxGearRatio ~= nil then
    VehicleMotor.getMinMaxGearRatio = Utils.overwrittenFunction(VehicleMotor.getMinMaxGearRatio, function(self, superFunc)
        local minRatio, maxRatio = superFunc(self)
        local vehicle = self.vehicle
        if vehicle == nil then return minRatio, maxRatio end

        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms == nil or spec_rms.activeEffects == nil then return minRatio, maxRatio end

        -- TRANSMISSION_SLIP_EFFECT
        local slipEffect = spec_rms.activeEffects.TRANSMISSION_SLIP_EFFECT
        if slipEffect ~= nil and slipEffect.value ~= nil then
            local modifier = tonumber(slipEffect.value) or 0

            if modifier >= 1 then
                return minRatio * 100, maxRatio * 100
            end

            spec_rms.slipAccumulatedMod = spec_rms.slipAccumulatedMod or 0

            local nowMs = g_currentMission.time
            local lastUpdateMs = spec_rms.slipLastUpdateMs or nowMs
            local dtSec = math.max((nowMs - lastUpdateMs) / 1000, 0)
            spec_rms.slipLastUpdateMs = nowMs
            if dtSec > TRANSMISSION_SLIP_RESUME_GAP_SECONDS then dtSec = 0 end

            local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6), 1.0)

            if modifier > 0 and minRatio ~= 0 and speedFactor > 0.5 then
                local motorAccel = self.motorRotAccelerationSmoothed
                local accelerationFactor = math.min(math.max(0, motorAccel / self.motorRotationAccelerationLimit * 5), 1.0)

                local step = TRANSMISSION_SLIP_CONVERGENCE_PER_SECOND * dtSec * (1 - math.min(speedFactor, 0.9))
                if spec_rms.slipAccumulatedMod < accelerationFactor then
                    spec_rms.slipAccumulatedMod = math.min(spec_rms.slipAccumulatedMod + step, 1.0)
                else
                    spec_rms.slipAccumulatedMod = math.max(spec_rms.slipAccumulatedMod - step, 0.0)
                end

                local dynamicModifier = modifier * spec_rms.slipAccumulatedMod
                minRatio = minRatio * (1 + dynamicModifier)
                maxRatio = maxRatio * (1 + dynamicModifier)
            end
        end

        -- CVT_SLIP_EFFECT
        local cvtSlipEffect = spec_rms.activeEffects.CVT_SLIP_EFFECT
        local isSliping = false
        if cvtSlipEffect ~= nil and cvtSlipEffect.value ~= nil and self.minForwardGearRatio ~= nil then
            local modifier = tonumber(cvtSlipEffect.value) or 0

            if modifier >= 1 then
                return minRatio * 100, maxRatio * 100
            end

            local nowMs = g_currentMission.time
            local lastUpdateMs = spec_rms.cvtSlipLastUpdateMs or nowMs
            local dtSec = math.max((nowMs - lastUpdateMs) / 1000, 0)
            spec_rms.cvtSlipLastUpdateMs = nowMs
            if dtSec > TRANSMISSION_SLIP_RESUME_GAP_SECONDS then dtSec = 0 end

            local lastAccelerationFactor = spec_rms.cvtSlipLastAccelerationFactor or 0
            local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6 / 2), 1.0)
            local loadFactor = vehicle:getMotorLoadPercentage() + 0.2
            local massFactor = vehicle:getTotalMass() / vehicle:getTotalMass(true)

            if modifier > 0 and minRatio ~= 0 and maxRatio ~= 0 and speedFactor < 0.5 then
                local decatPerSecond = 0.01 / modifier * math.max(speedFactor, 0.1) * 1 / loadFactor * 1 / massFactor
                local motorAccel = self.motorRotAccelerationSmoothed
                local accelLimit = math.max(tonumber(self.motorRotationAccelerationLimit) or 0, 0.000001)
                local accelerationFactor = math.clamp(motorAccel / accelLimit, 0, 1)
                if accelerationFactor < lastAccelerationFactor then
                    accelerationFactor = math.clamp(lastAccelerationFactor - decatPerSecond * dtSec, 0, 1)
                end
                spec_rms.cvtSlipLastAccelerationFactor = accelerationFactor
                isSliping = accelerationFactor >= 0.98 and speedFactor < 0.8

                local clampMin = math.min(minRatio, minRatio * 10)
                local clampMax = math.max(minRatio, minRatio * 10)
                minRatio = math.clamp(self.gearRatio * accelerationFactor, clampMin, clampMax)
            end
        end

        -- CVT_MAX_RATIO_MODIFIER
        local cvtMaxEffect = spec_rms.activeEffects.CVT_MAX_RATIO_MODIFIER
        local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6 / 2), 1.0)
        if cvtMaxEffect ~= nil and cvtMaxEffect.value ~= nil and self.minForwardGearRatio ~= nil and not isSliping and speedFactor > 0.5 then
            local value = tonumber(cvtMaxEffect.value) or 0
            minRatio = minRatio + minRatio * value * speedFactor
        end

        -- CVT_PRESSURE_DROP_CHANCE
        local pressureDropEffect = spec_rms.activeEffects.CVT_PRESSURE_DROP_CHANCE
        if pressureDropEffect ~= nil and pressureDropEffect.extraData ~= nil 
            and pressureDropEffect.extraData.status == "PROGRESS"
            and (pressureDropEffect.extraData.timer or 0) > 0 then
            minRatio = minRatio * 1.5
        end

        return minRatio, maxRatio
    end)
end

-- =========================================================
-- POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT
RMS_Breakdowns.EffectApplicators.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT = {
    getEffectName = function()
        return "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()

        if vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] == nil then
            vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = function(v, dt)
                
                if v:getIsMotorStarted() then
                    local spec = v.spec_RealisticMechanicalSystems
                    local effect = spec.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT
                    if effect and effect.value > 0 and effect.extraData.status ~= "IDLE" then
                        local motor = v:getMotor()
                        effect.extraData.timer = effect.extraData.timer + dt

                        if effect.extraData.timer > effect.value * 1000 and effect.extraData.status == "DELAYED" then
                            effect.extraData.timer = 0
                            effect.extraData.status = "PASSED"
                            if effect.extraData.backup then
                                effect.extraData.backup = motor.minGearRatio
                                motor.minGearRatio = 999.9
                            end
                            motor:applyTargetGear()
                        elseif effect.extraData.timer > effect.extraData.duration and effect.extraData.status == "PASSED" then
                            if effect.extraData.backup then
                                motor.minGearRatio = effect.extraData.backup
                            end
                            effect.extraData.status = "IDLE"
                        end
                    end
                end
            end
        end
    end,

    remove = function(vehicle, handler)

        local effectName = handler.getEffectName()
        if vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] ~= nil then
            vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = nil
        end
    end
}

if VehicleMotor ~= nil and VehicleMotor.applyTargetGear ~= nil then
    VehicleMotor.applyTargetGear = Utils.overwrittenFunction(VehicleMotor.applyTargetGear, function(self, superFunc)
        local vehicle = self.vehicle
        if vehicle ~= nil then
            local spec_rms = vehicle.spec_RealisticMechanicalSystems
            if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
                local effect = spec_rms.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT
                if effect ~= nil and effect.value ~= nil and effect.extraData.status == "IDLE" then
                    if effect.value >= 1.0 then
                        self.targetGear = self.previousGear
                        return superFunc(self)
                    end
                    effect.extraData.status = "DELAYED"
                    effect.extraData.timer = 0
                    return
                end
            end
        end
        return superFunc(self)
    end)
end

-- =========================================================

local function isHydraulicHoldDriftBlockedByFold(implement)
    if implement == nil then
        return false
    end

    if implement.getIsUnfolded ~= nil then
        local isUnfolded = implement:getIsUnfolded()
        if isUnfolded ~= nil then
            return not isUnfolded
        end
    end

    if implement.getFoldAnimTime ~= nil then
        local foldAnimTime = implement:getFoldAnimTime()
        if foldAnimTime ~= nil then
            return foldAnimTime < 0.99
        end
    end

    return false
end

local function setHydraulicHoldDriftSpeedLimitBypass(implement, enabled)
    if implement == nil or implement.doCheckSpeedLimit == nil then
        return
    end

    if implement.rmsHoldDriftOrigDoCheckSpeedLimit == nil then
        implement.rmsHoldDriftOrigDoCheckSpeedLimit = implement.doCheckSpeedLimit
        implement.doCheckSpeedLimit = function(obj, ...)
            if obj.rmsHoldDriftBypassSpeedLimit == true then
                local attacherVehicle = obj.getAttacherVehicle ~= nil and obj:getAttacherVehicle() or nil
                if attacherVehicle ~= nil then
                    return false
                end
                obj.rmsHoldDriftBypassSpeedLimit = false
            end

            local origFunc = obj.rmsHoldDriftOrigDoCheckSpeedLimit
            if origFunc ~= nil then
                return origFunc(obj, ...)
            end

            return false
        end
    end

    implement.rmsHoldDriftBypassSpeedLimit = enabled == true
end

local function restoreHydraulicHoldDriftSpeedLimitBypass(implement)
    if implement == nil then
        return
    end

    if implement.rmsHoldDriftOrigDoCheckSpeedLimit ~= nil then
        implement.doCheckSpeedLimit = implement.rmsHoldDriftOrigDoCheckSpeedLimit
        implement.rmsHoldDriftOrigDoCheckSpeedLimit = nil
    end

    implement.rmsHoldDriftBypassSpeedLimit = nil
end

-- HYDRAULIC_SPEED_MODIFIER
RMS_Breakdowns.EffectApplicators.HYDRAULIC_SPEED_MODIFIER = {

}

-- HYDRAULIC_HOLD_DRIFT_EFFEC
RMS_Breakdowns.EffectApplicators.HYDRAULIC_HOLD_DRIFT_EFFECT = {
    getEffectName = function()
        return "HYDRAULIC_HOLD_DRIFT_EFFECT"
    end,

    apply = function(vehicle, effectData, handler)
        local activeFunc = function(v, dt) 
            if v.spec_attacherJoints and v.spec_attacherJoints.attachedImplements and next(v.spec_attacherJoints.attachedImplements) ~= nil then
                for _, implementData in pairs(v.spec_attacherJoints.attachedImplements) do
                    if implementData.object ~= nil then
                        local implement = implementData.object
                        local jointDescIndex = implementData.jointDescIndex
                        local jointDesc = v.spec_attacherJoints.attacherJoints[jointDescIndex]
                        local jointTypeId = jointDesc ~= nil and jointDesc.jointType or nil
                        if jointDesc ~= nil then
                            local driftBlockedByFold = isHydraulicHoldDriftBlockedByFold(implement)
                            local isLowered = implement:getIsLowered()
                            -- Clear auto-drift marker when movement has finished in lowered state
                            -- or user switched direction to raising / implement is folded.
                            if jointDesc.rmsHoldDriftForced == true then
                                if driftBlockedByFold or (isLowered and not jointDesc.isMoving) or jointDesc.moveDown == false then
                                    jointDesc.rmsHoldDriftForced = false
                                end
                            end

                            -- Force slow auto-drop only from raised idle state.
                            if not driftBlockedByFold and not isLowered and not jointDesc.isMoving and jointDesc.moveDown == false and jointTypeId == 1 then
                                jointDesc.rmsHoldDriftForced = true
                                v:setJointMoveDown(jointDescIndex, true, false)
                            end

                            local bypassWorkSpeedLimit = jointDesc.rmsHoldDriftForced == true and jointDesc.moveDown == true and jointDesc.isMoving == true and not driftBlockedByFold
                            if bypassWorkSpeedLimit then
                                setHydraulicHoldDriftSpeedLimitBypass(implement, true)
                            else
                                restoreHydraulicHoldDriftSpeedLimitBypass(implement)
                            end
                        end
                    end
                end
            end
        end
        addFuncToActive(vehicle, handler.getEffectName(), activeFunc)
    end,

    remove = function(vehicle, handler)
        if vehicle.spec_attacherJoints ~= nil and vehicle.spec_attacherJoints.attachedImplements ~= nil then
            for _, implementData in pairs(vehicle.spec_attacherJoints.attachedImplements) do
                if implementData.object ~= nil then
                    restoreHydraulicHoldDriftSpeedLimitBypass(implementData.object)
                end

                local jointDesc = vehicle.spec_attacherJoints.attacherJoints[implementData.jointDescIndex]
                if jointDesc ~= nil then
                    jointDesc.rmsHoldDriftForced = false
                end
            end
        end

        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

function RMS_Breakdowns.applyHydraulicDamageToAttacher(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = self.spec_attacherJoints

    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local hydraulicHoldEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_HOLD_DRIFT_EFFECT
    local hydraulicModifier = (hydraulicEffect and hydraulicEffect.value) or 0
    local hydraulicHoldModifier = (hydraulicHoldEffect and hydraulicHoldEffect.value) or 0
    
    if hydraulicModifier == 0 and hydraulicHoldModifier == 0 then
        return superFunc(self, dt, ...)
    end

    local raisePerformance = math.max(0.05, 1.0 + hydraulicModifier)
    local holdDriftPerformance = math.max(tonumber(hydraulicHoldModifier) or 0, 0.01)

    for _, implement in ipairs(spec.attachedImplements) do
        if implement.object ~= nil then
            local jointDesc = spec.attacherJoints[implement.jointDescIndex]
            
            if jointDesc.rmsOriginalMoveDefaultTime == nil then
                jointDesc.rmsOriginalMoveDefaultTime = jointDesc.moveDefaultTime
            end

            -- Player requested raising: immediately disable forced hold-drift path
            -- in this same tick, so upward movement uses raise/default speed.
            if jointDesc.rmsHoldDriftForced == true and jointDesc.moveDown == false then
                jointDesc.rmsHoldDriftForced = false
            end

            if jointDesc.moveDown == false and hydraulicModifier ~= 0 then
                -- HYDRAULIC_SPEED_MODIFIER: slow down raising only.
                jointDesc.moveDefaultTime = jointDesc.rmsOriginalMoveDefaultTime / raisePerformance
            elseif jointDesc.moveDown == true and jointDesc.rmsHoldDriftForced == true and hydraulicHoldModifier > 0 then
                -- HYDRAULIC_HOLD_DRIFT_EFFECT: slow down only forced auto-drop.
                jointDesc.moveDefaultTime = jointDesc.rmsOriginalMoveDefaultTime / holdDriftPerformance
            else
                -- Manual lowering and any neutral state should stay at normal speed.
                jointDesc.moveDefaultTime = jointDesc.rmsOriginalMoveDefaultTime
            end
        end
    end

    local success, result = pcall(superFunc, self, dt, ...)

    for _, implement in ipairs(spec.attachedImplements) do
        if implement.object ~= nil then
            local jointDesc = spec.attacherJoints[implement.jointDescIndex]
            
            if jointDesc.rmsOriginalMoveDefaultTime ~= nil then
                jointDesc.moveDefaultTime = jointDesc.rmsOriginalMoveDefaultTime
            end
        end
    end

    if not success then
        log_hook_error("AttacherJoints.onUpdateTick", result)
        return
    end

    return result
end


function RMS_Breakdowns.applyHydraulicDamageToCylindered(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = self.spec_cylindered

    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local hydraulicModifier = (hydraulicEffect and hydraulicEffect.value) or 0
    if hydraulicModifier == 0 then
        return superFunc(self, dt, ...)
    end

    local performance = math.max(0.05, 1.0 + hydraulicModifier)

    for _, tool in ipairs(spec.movingTools) do
        if tool.rmsOriginalSpeeds == nil then
            tool.rmsOriginalSpeeds = {
                rotSpeed = tool.rotSpeed,
                transSpeed = tool.transSpeed,
                animSpeed = tool.animSpeed
            }
        end
        
        if tool.rotSpeed ~= nil then
            tool.rotSpeed = tool.rmsOriginalSpeeds.rotSpeed * performance
        end
        if tool.transSpeed ~= nil then
            tool.transSpeed = tool.rmsOriginalSpeeds.transSpeed * performance
        end
        if tool.animSpeed ~= nil then
            tool.animSpeed = tool.rmsOriginalSpeeds.animSpeed * performance
        end
    end

    local success, result = pcall(superFunc, self, dt, ...)

    for _, tool in ipairs(spec.movingTools) do
        if tool.rmsOriginalSpeeds ~= nil then
            if tool.rotSpeed ~= nil then
                tool.rotSpeed = tool.rmsOriginalSpeeds.rotSpeed
            end
            if tool.transSpeed ~= nil then
                tool.transSpeed = tool.rmsOriginalSpeeds.transSpeed
            end
            if tool.animSpeed ~= nil then
                tool.animSpeed = tool.rmsOriginalSpeeds.animSpeed
            end
        end
    end

    if not success then
        log_hook_error("Cylindered.onUpdate", result)
        return
    end

    return result
end


function RMS_Breakdowns.applyHydraulicDamageToFoldable(self, superFunc, direction, moveToMiddle, noEventSend)
    local rootVehicle = self:getRootVehicle()
    local spec = self.spec_foldable

    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local hydraulicModifier = (hydraulicEffect and hydraulicEffect.value) or 0
    if hydraulicModifier == 0 then
        return superFunc(self, direction, moveToMiddle, noEventSend)
    end

    local performance = math.max(0.05, 1.0 + hydraulicModifier)

    for _, foldingPart in ipairs(spec.foldingParts) do
        if foldingPart.rmsOriginalSpeedScale == nil then
            foldingPart.rmsOriginalSpeedScale = foldingPart.speedScale
        end

        foldingPart.speedScale = foldingPart.rmsOriginalSpeedScale * performance
    end


    local success, result = pcall(superFunc, self, direction, moveToMiddle, noEventSend)

    for _, foldingPart in ipairs(spec.foldingParts) do
        if foldingPart.rmsOriginalSpeedScale ~= nil then
            foldingPart.speedScale = foldingPart.rmsOriginalSpeedScale
        end
    end

    if not success then
        log_hook_error("Foldable.setFoldState", result)
        return
    end

    return result
end


function RMS_Breakdowns.applyHydraulicDamageToPlowRotation(self, superFunc, rotationMax, noEventSend, turnAnimationTime)
    local rootVehicle = self:getRootVehicle()
    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local hydraulicModifier = (hydraulicEffect and hydraulicEffect.value) or 0

    -- Keep the vanilla Plow event flow intact. In particular, the receiving
    -- side calls this function with noEventSend=true to prevent event echoes.
    local result = superFunc(self, rotationMax, noEventSend, turnAnimationTime)

    -- Stream/savegame synchronization supplies an explicit animation time and
    -- must not start the animation. Only adjust a newly started local animation.
    if hydraulicModifier ~= 0 and turnAnimationTime == nil then
        local performance = math.max(0.05, 1.0 + hydraulicModifier)
        local spec = self.spec_plow
        local turnAnimation = spec.rotationPart.turnAnimation

        if turnAnimation ~= nil then
            local direction = rotationMax and 1 or -1
            self:setAnimationSpeed(turnAnimation, direction * performance)
        end
    end

    return result
end


function RMS_Breakdowns.applyHydraulicDamageToPlowCenterRotation(self, superFunc, noEventSend)
    local rootVehicle = self:getRootVehicle()
    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local hydraulicModifier = (hydraulicEffect and hydraulicEffect.value) or 0

    local result = superFunc(self, noEventSend)

    if hydraulicModifier ~= 0 then
        local performance = math.max(0.05, 1.0 + hydraulicModifier)
        local spec = self.spec_plow
        local turnAnimation = spec.rotationPart.turnAnimation

        if turnAnimation ~= nil then
            local centerPosition = spec.ai.centerPosition
            local animTime = self:getAnimationTime(turnAnimation)

            if animTime ~= centerPosition then
                if animTime < centerPosition then
                    self:setAnimationSpeed(turnAnimation, performance)
                else
                    self:setAnimationSpeed(turnAnimation, -performance)
                end
            end
        end
    end

    return result
end

do
    if not RMS_Breakdowns._hydraulicSpeedHooksInstalled then
        local hydraulicSpeedHookDefs = {
            { objectName = "Plow", field = "setRotationMax", wrapperName = "applyHydraulicDamageToPlowRotation" },
            { objectName = "Plow", field = "setRotationCenter", wrapperName = "applyHydraulicDamageToPlowCenterRotation" },
            { objectName = "AttacherJoints", field = "onUpdateTick", wrapperName = "applyHydraulicDamageToAttacher" },
            { objectName = "Cylindered", field = "onUpdate", wrapperName = "applyHydraulicDamageToCylindered" },
            { objectName = "Foldable", field = "setFoldState", wrapperName = "applyHydraulicDamageToFoldable" }
        }

        for _, def in ipairs(hydraulicSpeedHookDefs) do
            local targetObject = _G[def.objectName]
            local wrapperFunc = RMS_Breakdowns[def.wrapperName]
            if targetObject ~= nil and targetObject[def.field] ~= nil and wrapperFunc ~= nil then
                targetObject[def.field] = Utils.overwrittenFunction(targetObject[def.field], wrapperFunc)
                log_dbg("HYDRAULIC hook installed:", string.format("%s.%s", def.objectName, def.field))
            else
                log_dbg("HYDRAULIC hook skipped:", string.format("%s.%s", def.objectName, def.field))
            end
        end

        RMS_Breakdowns._hydraulicSpeedHooksInstalled = true
    end
end

-- =========================================================
-- MAX_SPEED_MODIFIER
RMS_Breakdowns.EffectApplicators.MAX_SPEED_MODIFIER = {

}

function RMS_Breakdowns.getSpeedLimitOverwrite(vehicle, superFunc, onlyIfWorking)
    local speedLimit, doCheckSpeedLimit = superFunc(vehicle, onlyIfWorking)

    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms == nil or spec_rms.activeEffects == nil then
        return speedLimit, doCheckSpeedLimit
    end

    local effect = spec_rms.activeEffects.MAX_SPEED_MODIFIER
    if effect == nil or effect.value == nil then
        return speedLimit, doCheckSpeedLimit
    end

    local reduction = math.clamp(tonumber(effect.value) or 0, 0, 0.99)
    if reduction <= 0 then
        return speedLimit, doCheckSpeedLimit
    end

    local motor = vehicle:getMotor()

    if speedLimit == nil or speedLimit >= math.huge then
        local baseMaxMps = nil
        if motor ~= nil then
            baseMaxMps = tonumber(motor.maxForwardSpeedOrigin)
                or tonumber(motor.maxForwardSpeed)
                or (motor.getMaximumForwardSpeed ~= nil and tonumber(motor:getMaximumForwardSpeed()) or nil)
        end
        if baseMaxMps ~= nil then
            speedLimit = baseMaxMps * 3.6
        end
    end

    if speedLimit ~= nil and speedLimit < math.huge then
        speedLimit = speedLimit - speedLimit * reduction
    end

    return speedLimit or math.huge, doCheckSpeedLimit
end

-- =========================================================
-- ==========================================================
-- CONDITION_WEAR_MODIFIER
RMS_Breakdowns.EffectApplicators.CONDITION_WEAR_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraConditionWear = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraConditionWear = 0
    end
}

-- SERVICE_WEAR_MODIFIER
RMS_Breakdowns.EffectApplicators.SERVICE_WEAR_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraServiceWear = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraServiceWear = 0
    end
}

-- ENGINE_HEAT_MODIFIER
RMS_Breakdowns.EffectApplicators.ENGINE_HEAT_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraEngineHeat = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraEngineHeat = 0
    end
}

-- TRANSMISSION_HEAT_MODIFIER
RMS_Breakdowns.EffectApplicators.TRANSMISSION_HEAT_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraTransmissionHeat = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraTransmissionHeat = 0
    end
}

-- THERMOSTAT_HEALTH_MODIFIER
RMS_Breakdowns.EffectApplicators.THERMOSTAT_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.thermostatHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.thermostatHealth = 1.0
    end
}

-- RADIATOR_HEALTH_MODIFIER
RMS_Breakdowns.EffectApplicators.RADIATOR_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.radiatorHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.radiatorHealth = 1.0
    end
}

-- BATTERY_HEALTH_MODIFIER
RMS_Breakdowns.EffectApplicators.BATTERY_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.batteryHealth = math.max(1.0 + effectData.value, 0.0001)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.batteryHealth = 1.0
    end
}

-- ALTERNATOR_HEALTH_MODIFIER
RMS_Breakdowns.EffectApplicators.ALTERNATOR_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.alternatorHealth = math.max(1.0 + effectData.value, 0.0001)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.alternatorHealth = 1.0
    end
}

-- FAN_CLUTCH_MODIFIER
RMS_Breakdowns.EffectApplicators.FAN_CLUTCH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.fanClutchHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.fanClutchHealth = 1.0
    end
}

-- THERMOSTAT_STUCK_EFFECT
RMS_Breakdowns.EffectApplicators.THERMOSTAT_STUCK_EFFECT = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems


        if spec.thermostatStuckedPosition == nil or spec.thermostatStuckedPosition < 0 then
            spec.thermostatStuckedPosition = spec.thermostatState
        end
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.thermostatStuckedPosition = nil
    end
}

-- TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER
RMS_Breakdowns.EffectApplicators.TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionThermostatHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionThermostatHealth = 1.0
    end
}

-- TRANSMISSION_THERMOSTAT_STUCK_EFFECT
RMS_Breakdowns.EffectApplicators.TRANSMISSION_THERMOSTAT_STUCK_EFFECT = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems

        if spec.transmissionThermostatStuckedPosition == nil or spec.transmissionThermostatStuckedPosition < 0 then
            spec.transmissionThermostatStuckedPosition = spec.transmissionThermostatState
        end
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionThermostatStuckedPosition = nil
    end
}

-- ==========================================================
-- IDLE_HUNTING_EFFECT
local function updateIdleHuntingMotor(motor, effectData, dt, rpmBackup, shouldHunt, allowRestore, resetWhenInactive)
    if shouldHunt then
        if rpmBackup == nil or rpmBackup == 0 then
            rpmBackup = motor.minRpm
        end
        effectData.extraData.timer = (effectData.extraData.timer or 0) + dt
        motor.minRpm = rpmBackup * (1 + effectData.value * math.sin(2 * math.pi * effectData.extraData.timer / effectData.extraData.period))
    else
        local restored = false
        if allowRestore and rpmBackup ~= nil and rpmBackup ~= 0 and rpmBackup ~= motor.minRpm then
            motor.minRpm = rpmBackup
            restored = true
        end
        if resetWhenInactive or restored then
            effectData.extraData.timer = 0
        end
    end

    return rpmBackup
end

RMS_Breakdowns.EffectApplicators.IDLE_HUNTING_EFFECT = {
    getEffectName = function()
        return "IDLE_HUNTING_EFFECT" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()
        local motor = vehicle:getMotor()
        effectData.extraData.rpmBackup = motor.minRpm

        local activeFunc = function(v, dt)
            effectData.extraData.rpmBackup = updateIdleHuntingMotor(
                motor,
                effectData,
                dt,
                effectData.extraData.rpmBackup,
                v:getIsMotorStarted() and v:getLastSpeed() < 0.01,
                true,
                false
            )
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- ==========================================================
-- GLOW_PLUG_COLD_IDLE_EFFECT
RMS_Breakdowns.EffectApplicators.GLOW_PLUG_COLD_IDLE_EFFECT = {
    getEffectName = function()
        return "GLOW_PLUG_COLD_IDLE_EFFECT"
    end,

    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local motor = vehicle:getMotor()
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec.glowPlugColdIdleRpmBackup == nil then
            spec.glowPlugColdIdleRpmBackup = motor.minRpm
        end
        local activeFunc = function(v, dt)
            local spec = v.spec_RealisticMechanicalSystems
            local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects[effectName] or nil
            if effect == nil or effect.extraData == nil then
                return
            end

            local coldThreshold = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
            local engineTemperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, coldThreshold, -80, 160)
            local otherIdleHuntingEffect = spec.activeEffects.IDLE_HUNTING_EFFECT
            local otherIdleHuntingActive = otherIdleHuntingEffect ~= nil
            local shouldHunt = spec.preheatColdStartFaultSeverity >= 2
                and engineTemperature < coldThreshold
                and v:getIsMotorStarted()
                and v:getLastSpeed() < 0.01
                and not otherIdleHuntingActive

            if otherIdleHuntingActive and spec.glowPlugColdIdleRpmBackup ~= nil then
                otherIdleHuntingEffect.extraData = otherIdleHuntingEffect.extraData or {}
                otherIdleHuntingEffect.extraData.rpmBackup = spec.glowPlugColdIdleRpmBackup
            end

            spec.glowPlugColdIdleRpmBackup = updateIdleHuntingMotor(
                motor,
                effect,
                dt,
                spec.glowPlugColdIdleRpmBackup,
                shouldHunt,
                not otherIdleHuntingActive,
                true
            )

        end

        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local motor = vehicle:getMotor()
        if spec ~= nil and spec.glowPlugColdIdleRpmBackup ~= nil then
            local otherIdleHuntingEffect = spec.activeEffects.IDLE_HUNTING_EFFECT
            if otherIdleHuntingEffect ~= nil then
                otherIdleHuntingEffect.extraData = otherIdleHuntingEffect.extraData or {}
                otherIdleHuntingEffect.extraData.rpmBackup = spec.glowPlugColdIdleRpmBackup
            end
            motor.minRpm = spec.glowPlugColdIdleRpmBackup
        end
        spec.glowPlugColdIdleRpmBackup = nil
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- ==========================================================
-- DARK_EXHAUST_EFFECT
RMS_Breakdowns.EffectApplicators.DARK_EXHAUST_EFFECT = {    
    apply = function(vehicle, effectData, handler)
        local originalMinRpmColorName = "exhaustEffectsMinRpmColor"
        local originalMaxRpmColorName = "exhaustEffectsMaxRpmColor"
        local effect = vehicle.spec_motorized.exhaustEffects[#vehicle.spec_motorized.exhaustEffects]

        if effect == nil or effect.minRpmColor == nil or effect.maxRpmColor == nil then
            return
        end
        
        if vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMinRpmColorName] == nil then
            vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMinRpmColorName] = { 
                effect.minRpmColor[1],
                effect.minRpmColor[2],
                effect.minRpmColor[3],
                effect.minRpmColor[4]
            }
        end
        if vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMaxRpmColorName] == nil then
            vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMaxRpmColorName] = {
                effect.maxRpmColor[1],
                effect.maxRpmColor[2],
                effect.maxRpmColor[3],
                effect.maxRpmColor[4]
            }
        end

        local originalMinRpmColorValue = vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMinRpmColorName]
        local originalMaxRpmColorValue = vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMaxRpmColorName]
        
	    if effect ~= nil then
		    effect.minRpmColor = {0.015, 0.015, 0.02, originalMinRpmColorValue[4] * effectData.value * 6}
		    effect.maxRpmColor = {0.015, 0.015, 0.02, originalMaxRpmColorValue[4] * effectData.value * 12}
	    end

    end,

    remove = function(vehicle, handler)
        local originalMinRpmColorName = "exhaustEffectsMinRpmColor"
        local originalMaxRpmColorName = "exhaustEffectsMaxRpmColor"
        local originalMinRpmColorValue = vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMinRpmColorName]
        local originalMaxRpmColorValue = vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMaxRpmColorName]
        local effect = vehicle.spec_motorized.exhaustEffects[#vehicle.spec_motorized.exhaustEffects]
        if originalMinRpmColorValue ~= nil then
            effect.minRpmColor[1] = originalMinRpmColorValue[1]
            effect.minRpmColor[2] = originalMinRpmColorValue[2]
            effect.minRpmColor[3] = originalMinRpmColorValue[3]
            effect.minRpmColor[4] = originalMinRpmColorValue[4]
            vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMinRpmColorName] = nil
        end
        if originalMaxRpmColorValue ~= nil then
            effect.maxRpmColor[1] = originalMaxRpmColorValue[1]
            effect.maxRpmColor[2] = originalMaxRpmColorValue[2]
            effect.maxRpmColor[3] = originalMaxRpmColorValue[3]
            effect.maxRpmColor[4] = originalMaxRpmColorValue[4]
            vehicle.spec_RealisticMechanicalSystems.originalFunctions[originalMaxRpmColorName] = nil
        end
    end
}

-- ==========================================================
-- ELECTRICAL_CONTACT_RESISTANCE_EFFECT
RMS_Breakdowns.EffectApplicators.ELECTRICAL_CONTACT_RESISTANCE_EFFECT = {
    getEffectName = function()
        return "ELECTRICAL_CONTACT_RESISTANCE_EFFECT" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()

        local activeFunc = function(v, dt)
                local spec = v.spec_RealisticMechanicalSystems
                local effect = spec.activeEffects.ELECTRICAL_CONTACT_RESISTANCE_EFFECT
                if v.isServer and v:getIsMotorStarted() then
                    if effect and effect.value > 0 then
                        if effect.extraData.status == "IDLE" then
                            local chance = RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value)
                            if math.random() < chance then
                                effect.extraData.status = "SHORTC"
                                effect.extraData.timer = 1000
                                spec.extraCurrentPeak = 1000
                            end
                        elseif effect.extraData.status == "SHORTC" then
                            effect.extraData.timer = math.max(effect.extraData.timer - dt, 0)
                            if effect.extraData.timer <= 0 then
                                effect.extraData.status = "IDLE"
                                effect.extraData.timer = 0
                                spec.extraCurrentPeak = 0
                            end
                        end
                    end
                else
                    spec.extraCurrentPeak = 0
                end
            end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}



-- ==========================================================
-- SOUND_EFFECTS

local function rmsStopAndResetNoiseSample(sample)
    if sample == nil then return end
    RMS_SoundManager.setSamplePlaying(sample, false, 0, 0)
    RMS_SoundManager.setSampleVolumeOffset(sample, 0)
    RMS_SoundManager.setSamplePitchOffset(sample, 0)
    if sample.rmsOriginalLoops ~= nil then
        sample.loops = sample.rmsOriginalLoops
    end
    if sample.rmsOriginalVolumeScale ~= nil then
        sample.volumeScale = sample.rmsOriginalVolumeScale
    end
end

local function rmsUpdateNoiseGate(spec, effectName, targetGate, dt)
    spec.__rmsNoiseGates = spec.__rmsNoiseGates or {}
    local previousGate = math.clamp(tonumber(spec.__rmsNoiseGates[effectName]) or 0, 0, 1)
    local attackMs = 220
    local releaseMs = 520
    local responseMs = targetGate > previousGate and attackMs or releaseMs
    local alpha = math.min((tonumber(dt) or 0) / math.max(responseMs, 1), 1)
    local gate = previousGate + (targetGate - previousGate) * alpha
    gate = math.clamp(gate, 0, 1)
    spec.__rmsNoiseGates[effectName] = gate
    return gate
end

local function createEngineNoiseEffectApplicator(effectName, sampleName, gateMode)
    return {
        getEffectName = function()
            return effectName
        end,

        apply = function(vehicle, effectData, handler)
            log_dbg(string.format("Applying %s effect", effectName))
            local activeFunc = function(v, dt)
                local spec_rms = v.spec_RealisticMechanicalSystems
                if spec_rms == nil or spec_rms.samples == nil then return end
                local motor = v:getMotor()
                if motor == nil then return end

                local sample = spec_rms.samples[sampleName]
                if sample == nil then return end

                local currentEffect = spec_rms.activeEffects and spec_rms.activeEffects[effectName]
                local baseVolumeScale = math.clamp(tonumber(currentEffect and currentEffect.value) or tonumber(effectData.value) or 1, 0, 2)

                if not v:getIsMotorStarted() then
                    rmsStopAndResetNoiseSample(sample)
                    if spec_rms.__rmsNoiseGates ~= nil then
                        spec_rms.__rmsNoiseGates[effectName] = nil
                    end
                    return
                end

                local minRpm = tonumber(motor.minRpm) or 800
                local maxRpm = math.max(tonumber(motor.maxRpm) or (minRpm + 1), minRpm + 1)
                local lastRpm = (motor.getLastModulatedMotorRpm ~= nil and tonumber(motor:getLastModulatedMotorRpm())) or tonumber(motor.lastMotorRpm) or minRpm
                local rpmN = math.clamp((lastRpm - minRpm) / (maxRpm - minRpm), 0, 1)
                local loadN = math.clamp(tonumber(v:getMotorLoadPercentage()) or 0, 0, 1)
                local boostN = math.clamp(tonumber(motor.lastTurboScale) or 0, 0, 1)
                local hotN = math.clamp(((tonumber(spec_rms.engineTemperature) or 0) - 70) / 40, 0, 1)
                local speedMps = tonumber(v:getLastSpeed()) or 0

                local dynamicIntensity =
                    (0.30 + 0.70 * rpmN)
                    * (0.65 + 0.35 * loadN)
                    * (0.70 + 0.30 * hotN)
                dynamicIntensity = math.clamp(dynamicIntensity, 0, 1.6)

                local gate = 1
                if gateMode == "boost" then
                    local boostThreshold = 0.02
                    local targetGate = math.clamp((boostN - boostThreshold) / (1 - boostThreshold), 0, 1)
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, targetGate, dt)
                    baseVolumeScale = baseVolumeScale * gate
                elseif gateMode == "speed" then
                    local speedThresholdMps = 0.20
                    local fullSpeedMps = 2.00
                    local targetGate = math.clamp((speedMps - speedThresholdMps) / (fullSpeedMps - speedThresholdMps), 0, 1)
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, targetGate, dt)
                    baseVolumeScale = baseVolumeScale * gate
                end

                if baseVolumeScale <= 0.02 then
                    if (gateMode == "boost" or gateMode == "speed") and gate > 0.001 then
                        baseVolumeScale = 0.02
                    else
                        rmsStopAndResetNoiseSample(sample)
                        if spec_rms.__rmsNoiseGates ~= nil then
                            spec_rms.__rmsNoiseGates[effectName] = nil
                        end
                        return
                    end
                end

                if sample.rmsOriginalLoops == nil then
                    sample.rmsOriginalLoops = sample.loops
                end
                if sample.rmsOriginalVolumeScale == nil then
                    sample.rmsOriginalVolumeScale = sample.volumeScale
                end
                sample.loops = 0
                sample.volumeScale = sample.rmsOriginalVolumeScale * baseVolumeScale

                RMS_SoundManager.setSamplePlaying(sample, true)

                RMS_SoundManager.setSampleVolumeOffset(sample, 0)
                local pitchOffset
                if sampleName == "turboWhistle" then
                    local boostThreshold = 0.02
                    local boostGate = math.clamp((boostN - boostThreshold) / (1 - boostThreshold), 0, 1)
                    pitchOffset = (0.20 * boostGate + 0.16 * (rpmN ^ 1.20) * boostGate + 0.03 * loadN * boostGate) * gate
                elseif sampleName == "fanNoice" then
                    pitchOffset = 0
                elseif sampleName == "wheelHubBearingNoise" then
                    local speedN = math.clamp(speedMps / 15.0, 0, 1)
                    pitchOffset = (0.12 * (speedN ^ 1.10) + 0.03 * loadN * speedN) * gate
                elseif sampleName == "wheelSeizureGrind" then
                    local speedN = math.clamp(speedMps / 12.0, 0, 1)
                    pitchOffset = (0.06 * (speedN ^ 1.05) + 0.05 * loadN * speedN) * gate
                elseif sampleName == "vibrationNoice" then
                    local speedN = math.clamp(speedMps / 15.0, 0, 1)
                    pitchOffset = (0.08 * (speedN ^ 1.05) + 0.02 * loadN * speedN) * gate
                else
                    pitchOffset = 0.24 * (rpmN ^ 1.35) + 0.04 * dynamicIntensity * rpmN
                end
                RMS_SoundManager.setSamplePitchOffset(sample, pitchOffset)
            end

            addFuncToActive(vehicle, effectName, activeFunc)
        end,

        remove = function(vehicle, handler)
            log_dbg(string.format("Removing %s effect", effectName))
            local spec_rms = vehicle.spec_RealisticMechanicalSystems
            if spec_rms ~= nil and spec_rms.samples ~= nil then
                rmsStopAndResetNoiseSample(spec_rms.samples[sampleName])
                if spec_rms.__rmsNoiseGates ~= nil then
                    spec_rms.__rmsNoiseGates[effectName] = nil
                end
            end
            removeFuncFromActive(vehicle, handler.getEffectName())
        end
    }
end

RMS_Breakdowns.EffectApplicators.ENGINE_KNOCKING_NOISE_EFFECT = createEngineNoiseEffectApplicator("ENGINE_KNOCKING_NOISE_EFFECT", "engineKnocking", nil)
RMS_Breakdowns.EffectApplicators.VALVE_TRAIN_NOISE_EFFECT = createEngineNoiseEffectApplicator("VALVE_TRAIN_NOISE_EFFECT", "valveTrainNoise", nil)
RMS_Breakdowns.EffectApplicators.TURBO_WHISTLE_NOISE_EFFECT = createEngineNoiseEffectApplicator("TURBO_WHISTLE_NOISE_EFFECT", "turboWhistle", "boost")
RMS_Breakdowns.EffectApplicators.FAN_CLUTCH_NOISE_EFFECT = createEngineNoiseEffectApplicator("FAN_CLUTCH_NOISE_EFFECT", "fanNoice", nil)
RMS_Breakdowns.EffectApplicators.VIBRATION_NOISE_EFFECT = createEngineNoiseEffectApplicator("VIBRATION_NOISE_EFFECT", "vibrationNoice", "speed")
RMS_Breakdowns.EffectApplicators.WHEEL_HUB_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("WHEEL_HUB_BEARING_NOISE_EFFECT", "wheelHubBearingNoise", "speed")
RMS_Breakdowns.EffectApplicators.WHEEL_SEIZURE_GRIND_NOISE_EFFECT = createEngineNoiseEffectApplicator("WHEEL_SEIZURE_GRIND_NOISE_EFFECT", "wheelSeizureGrind", "speed")


-- ==========================================================
-- CVT_PRESSURE_DROP_CHANCE
RMS_Breakdowns.EffectApplicators.CVT_PRESSURE_DROP_CHANCE = {
    getEffectName = function()
        return "CVT_PRESSURE_DROP_CHANCE"
    end,

    apply = function(vehicle, effectData, handler)
        local motor = vehicle:getMotor()
        if motor == nil then return end
        if motor.minForwardGearRatio == nil then return end
        local effectName = handler.getEffectName()

        local activeFunc = function(v, dt)

            if v:getIsMotorStarted() and v:getLastSpeed() > 1 then
                local effect = v.spec_RealisticMechanicalSystems.activeEffects.CVT_PRESSURE_DROP_CHANCE
                if effect == nil then
                    return
                end
                effect.extraData = effect.extraData or {}
                effect.extraData.status = tostring(effect.extraData.status or "IDLE")
                effect.extraData.timer = tonumber(effect.extraData.timer) or 0
                effect.extraData.duration = tonumber(effect.extraData.duration) or 200

                if v.isServer and effect.extraData.status == 'IDLE' and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                    effect.extraData.status = 'DROP'
                    effect.extraData.timer = effect.extraData.duration

                    RMS_EffectSyncEvent.send(v, handler.getEffectName(), "DROP", effect.extraData.timer, 0, 0)
                end
                if effect.extraData.status == 'DROP' and effect.extraData.timer > 0 then
                    effect.extraData.status = 'PROGRESS'
                end
                if effect.extraData.status == 'PROGRESS' then
                    effect.extraData.timer = effect.extraData.timer - dt
                end
                if effect.extraData.timer <= 0 then
                    effect.extraData.timer = 0
                    effect.extraData.status = 'IDLE'
                end
            end
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- ==========================================================
-- ENGINE_STALLS_CHANCE
RMS_Breakdowns.EffectApplicators.ENGINE_STALLS_CHANCE = {
    getEffectName = function() return "ENGINE_STALLS_CHANCE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)

            if not v.isServer then return end

            if v:getIsMotorStarted() and not v:getIsAIActive() then
                local effect = v.spec_RealisticMechanicalSystems.activeEffects.ENGINE_STALLS_CHANCE
                if effect and effect.value > 0 then
                    if math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                        if v.stopMotor then
                            v:stopMotor()

                            RMS_EffectSyncEvent.send(v, "ENGINE_STALLS_CHANCE", "STALLED")

                            if v:getIsActiveForInput(true) then
                                g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_engine_stalled_message"), 5000) 
                            end
                        end
                    end
                end
            end
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end,
}

-- ==========================================================
-- PTO_AUTO_DISENGAGE_CHANCE
RMS_Breakdowns.EffectApplicators.PTO_AUTO_DISENGAGE_CHANCE = {
    getEffectName = function() return "PTO_AUTO_DISENGAGE_CHANCE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()

        local function hasActivePtoLoad(rootVehicle)
            if rootVehicle == nil then
                return false
            end

            local ptoActive = rootVehicle.getIsPowerTakeOffActive ~= nil and rootVehicle:getIsPowerTakeOffActive() or false
            local ptoConsuming = rootVehicle.getDoConsumePtoPower ~= nil and rootVehicle:getDoConsumePtoPower() or false
            local ptoRpm = rootVehicle.getPtoRpm ~= nil and (tonumber(rootVehicle:getPtoRpm()) or 0) or 0
            local ptoTorque = 0

            if PowerConsumer ~= nil and PowerConsumer.getTotalConsumedPtoTorque ~= nil then
                local ok, torqueValue = pcall(PowerConsumer.getTotalConsumedPtoTorque, rootVehicle, nil, nil, true)
                if ok then
                    ptoTorque = tonumber(torqueValue) or 0
                end
            end

            return ptoActive or ptoConsuming or ptoRpm > 10 or ptoTorque > 0.001
        end

        local function disengagePtoConsumers(rootVehicle)
            local turnedOff = false
            local visited = {}

            local function walk(vehicleObj)
                if vehicleObj == nil or visited[vehicleObj] then
                    return
                end
                visited[vehicleObj] = true

                local isTurnedOn = vehicleObj.getIsTurnedOn ~= nil and vehicleObj:getIsTurnedOn() or false
                if isTurnedOn and vehicleObj.setIsTurnedOn ~= nil then
                    vehicleObj:setIsTurnedOn(false)
                    turnedOff = true
                end

                if vehicleObj.getAttachedImplements ~= nil then
                    local implements = vehicleObj:getAttachedImplements() or {}
                    for _, implement in pairs(implements) do
                        if implement ~= nil and implement.object ~= nil then
                            walk(implement.object)
                        end
                    end
                end
            end

            walk(rootVehicle)
            return turnedOff
        end

        local activeFunc = function(v, dt)

            local effect = v.spec_RealisticMechanicalSystems.activeEffects[effectName]
            if effect == nil or (tonumber(effect.value) or 0) <= 0 then
                return
            end

            effect.extraData = effect.extraData or {}
            if effect.extraData.status == nil then
                effect.extraData.status = "IDLE"
            end

            if effect.extraData.status == "DISENGAGED" then
                if disengagePtoConsumers(v) then
                    if v:getIsActiveForInput(true) then
                        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_pto_auto_disengage_message"), 4000)
                    end
                end
                effect.extraData.status = "IDLE"
                return
            end

            if not v.isServer then
                return
            end

            if not hasActivePtoLoad(v) then
                return
            end

            if effect.extraData.status == "IDLE" and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                effect.extraData.status = "DISENGAGED"
                RMS_EffectSyncEvent.send(v, effectName, "DISENGAGED", 0, 0, 0)
            end
        end

        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- ==========================================================
-- ENGINE_HARD_START_MODIFIER

local function tryStartMotor(dt, value, engTemp, batV)
    local tempFactor = 0
    local batFactor = 1
    local modValue = value
    if engTemp <= -10 then
        tempFactor = math.max((-10 - engTemp) / 2, 0)
        modValue = modValue + tempFactor
    elseif engTemp >= 30 then
        local hotT = math.clamp((engTemp - 30) / 60, 0, 1)
        local hotFactor = 1.0 - 0.3 * hotT
        modValue = modValue * hotFactor
    end

    if batV ~= nil then
        local t = math.clamp((12.2 - batV) / 0.5, 0, 1)
        batFactor = 1 + (t * t)
        modValue = modValue * batFactor
    end
    local mtbfInMinutes = modValue / 60
    local chance = RMS_Utils.getChancePerFrameFromMeanTime(dt, mtbfInMinutes)
    local random = math.random()
    if random < chance then return true end
    return false
end

local function applyHardStartModifier(vehicle, effectName)
    local activeFunc = function(v, dt)
        local spec = v.spec_RealisticMechanicalSystems
        if spec == nil then return end
        local effect = spec.activeEffects ~= nil and spec.activeEffects[effectName] or nil
        if effect == nil or effect.extraData == nil then
            return
        end

        local motorStartDelay = 1500
        local startFadeMs = 0
        local endFadeMs = -1500
        local crankingPitchOffset = 0

        if effect.extraData.status == "CRANKING" then
            if effect.extraData.preCrankVoltageV == nil then
                effect.extraData.preCrankVoltageV = spec.batteryTerminalVoltageV or spec.batteryOpenCircuitVoltageV or 12.2
            end

            crankingPitchOffset = getStarterCrankingPitchOffset(effect.extraData.preCrankVoltageV)
        elseif effect.extraData.preCrankVoltageV ~= nil then
            crankingPitchOffset = getStarterCrankingPitchOffset(effect.extraData.preCrankVoltageV)
        end

        effect.extraData.timer = math.max((effect.extraData.timer or 0) - dt, endFadeMs)

        if v.isClient and effect.extraData.status == "PASSED" then
            playStarterCrankingEndSample(spec, crankingPitchOffset)
        end

        if effect.extraData.timer <= startFadeMs and effect.extraData.timer >= endFadeMs then
            local baseVolume = spec.samples.starterCrankingEnd.current.volume or 2.0
            local t = math.clamp(math.abs(effect.extraData.timer / endFadeMs), 0, 1)
            local easedT = t * t
            local offset = math.max(-(baseVolume * easedT), -0.65)

            if RMS_SoundManager.getIsSamplePlaying(spec.samples.starterCrankingEnd) then
                RMS_SoundManager.setSampleVolumeOffset(spec.samples.starterCrankingEnd, offset)
            end
        end

        if effect.extraData.timer <= 0 and effect.extraData.status == "PASSED" then
            v:startMotor(false, true)
            effect.extraData.status = "IDLE"
            effect.extraData.preCrankVoltageV = nil
            effect.extraData.automaticCrank = false
        end

        local startRequestActive = getIsStarterRequestActive(v, effect)
        if not v:getIsMotorStarted() and startRequestActive and effect.extraData.status == "CRANKING" then
            local rawEngineTemp = spec.rawEngineTemperature or spec.engineTemperature or -99
            if v.isServer
                and effect.extraData.blockStart ~= true
                and tryStartMotor(dt, effect.value, rawEngineTemp, effect.extraData.preCrankVoltageV) then
                effect.extraData.timer = motorStartDelay
                effect.extraData.status = "PASSED"
                RMS_Preheat.onCrankPassed(v)
                if v.isClient then
                    playStarterCrankingEndSample(spec, crankingPitchOffset)
                end
                RMS_EffectSyncEvent.send(v, effectName, "PASSED", motorStartDelay, 0, 0)
            end
        elseif not startRequestActive and effect.extraData.status == "CRANKING" then
            effect.extraData.status = "IDLE"
            effect.extraData.preCrankVoltageV = nil
            effect.extraData.automaticCrank = false
        end

        syncStarterCrankingSample(v)
    end

    addFuncToActive(vehicle, effectName, activeFunc)
end

local function removeHardStartModifier(vehicle, effectName)
    local effect = vehicle.spec_RealisticMechanicalSystems
        and vehicle.spec_RealisticMechanicalSystems.activeEffects
        and vehicle.spec_RealisticMechanicalSystems.activeEffects[effectName]
        or nil
    if effect ~= nil and effect.extraData ~= nil then
        effect.extraData.status = "IDLE"
        effect.extraData.timer = 0
        effect.extraData.preCrankVoltageV = nil
        effect.extraData.automaticCrank = false
    end
    syncStarterCrankingSample(vehicle)
    removeFuncFromActive(vehicle, effectName)
end

RMS_Breakdowns.EffectApplicators.ENGINE_HARD_START_MODIFIER = {
    getEffectName = function() return "ENGINE_HARD_START_MODIFIER" end,
    apply = function(vehicle, effectData, handler)
        applyHardStartModifier(vehicle, handler.getEffectName())
    end,
    remove = function(vehicle, handler)
        removeHardStartModifier(vehicle, handler.getEffectName())
    end
}

RMS_Breakdowns.EffectApplicators.GLOW_PLUG_HARD_START_MODIFIER = {
    getEffectName = function() return "GLOW_PLUG_HARD_START_MODIFIER" end,
    apply = function(vehicle, effectData, handler)
        applyHardStartModifier(vehicle, handler.getEffectName())
    end,
    remove = function(vehicle, handler)
        removeHardStartModifier(vehicle, handler.getEffectName())
    end
}

function RMS_Breakdowns.onStartButtonAction(self, actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory, binding)
    local spec = self ~= nil and self.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    local value = tonumber(inputValue) or 0
    local isPressed = binding ~= nil and binding.isPressed == true
    local currentlyHeld = isPressed or value > 0.5
    local wasHeld = spec.startButtonHeld == true

    local _prevStartButtonDown = spec.startButtonDown
    local _prevStartButtonUp = spec.startButtonUp
    local _prevStartButtonHeld = spec.startButtonHeld

    spec.startButtonDown = currentlyHeld and not wasHeld
    spec.startButtonUp = not currentlyHeld and wasHeld
    spec.startButtonHeld = currentlyHeld

    if _prevStartButtonDown ~= spec.startButtonDown or _prevStartButtonUp ~= spec.startButtonUp or _prevStartButtonHeld ~= spec.startButtonHeld then
        RMS_StartButtonEvent.send(self, spec.startButtonDown, spec.startButtonHeld, spec.startButtonUp)
    end

    if spec.startButtonDown then
        local wasPreheatFailed = RMS_Preheat.isFailed(self)
        RMS_Preheat.requestStart(self)

        if wasPreheatFailed then
            return
        end

        local automaticMotorStartEnabled = g_currentMission ~= nil
            and g_currentMission.missionInfo ~= nil
            and g_currentMission.missionInfo.automaticMotorStartEnabled == true

        if not automaticMotorStartEnabled then
            if actionName == InputAction.TOGGLE_MOTOR_STATE then
                Motorized.actionEventToggleMotorState(self, actionName, inputValue, callbackState, isAnalog)
            elseif actionName == InputAction.MOTOR_STATE_ON then
                Motorized.actionEventSetMotorStateOn(self, actionName, inputValue, callbackState, isAnalog)
            end
        end
    end
end

local function isColdGlowPlugStartBlocked(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle or spec.activeEffects == nil then
        return false
    end

    local effect = spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER

    return effect ~= nil
        and effect.extraData ~= nil
        and effect.extraData.blockStart == true
        and RMS_Preheat.getRequiredDurationMs(vehicle) > 0
end

function RMS_Breakdowns.getCanStartAIVehicle(self, superFunc, ...)
    if not superFunc(self, ...) then
        return false
    end

    if self.getIsMotorStarted ~= nil
        and not self:getIsMotorStarted()
        and isColdGlowPlugStartBlocked(self) then
        return false
    end

    return true
end

function RMS_Breakdowns.startMotor(self, superFunc, noEventSend, passed)
    local spec = self.spec_RealisticMechanicalSystems
    local engineFailure = spec and spec.activeEffects.ENGINE_FAILURE
    local engineHardStart = spec and spec.activeEffects.ENGINE_HARD_START_MODIFIER
    local glowPlugHardStart = spec and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER
    if glowPlugHardStart ~= nil and not RMS_Preheat.shouldApplyGlowPlugHardStart(self) then
        glowPlugHardStart = nil
    end
    local isGlowPlugStartBlocked = glowPlugHardStart ~= nil
        and glowPlugHardStart.extraData.blockStart == true

    if self:getIsAIActive() and not engineFailure then
        if isColdGlowPlugStartBlocked(self) then
            return
        end

        superFunc(self, noEventSend)
        return
    end

    if RMS_Preheat.shouldDeferStart(self, passed) then
        return
    end

    local selectedHardStart = engineHardStart
    local selectedHardStartId = "ENGINE_HARD_START_MODIFIER"
    if glowPlugHardStart ~= nil
        and (isGlowPlugStartBlocked
            or selectedHardStart == nil
            or glowPlugHardStart.value > selectedHardStart.value) then
        selectedHardStart = glowPlugHardStart
        selectedHardStartId = "GLOW_PLUG_HARD_START_MODIFIER"
    end

    local automaticMotorStartEnabled = g_currentMission ~= nil
        and g_currentMission.missionInfo ~= nil
        and g_currentMission.missionInfo.automaticMotorStartEnabled == true
    local hasManualStartInput = spec ~= nil and (spec.startButtonHeld == true
        or spec.startButtonDown == true
        or RMS_Preheat.isAutomaticCrankActive(self))
    local isAutomaticStartAttempt = automaticMotorStartEnabled and not hasManualStartInput


    if spec == nil or (engineFailure == nil and selectedHardStart == nil) or passed then
        superFunc(self, noEventSend)
        return
    end

    if engineFailure then
        if engineFailure.extraData.starter then
            if isAutomaticStartAttempt then
                return
            end
            if engineFailure.extraData.status == 'IDLE' then
                local automaticCrank = RMS_Preheat.isAutomaticCrankActive(self)
                engineFailure.extraData.status = 'CRANKING'
                engineFailure.extraData.automaticCrank = automaticCrank
                RMS_EffectSyncEvent.send(self, 'ENGINE_FAILURE', "CRANKING", 0, automaticCrank and 1 or 0, 0)
            end
        end
        return
    end

    if selectedHardStart and selectedHardStart.extraData.status == 'IDLE' then
        if isAutomaticStartAttempt then
            return
        end
        local automaticCrank = RMS_Preheat.isAutomaticCrankActive(self)
        selectedHardStart.extraData.status = 'CRANKING'
        selectedHardStart.extraData.automaticCrank = automaticCrank
        RMS_EffectSyncEvent.send(self, selectedHardStartId, "CRANKING", 0, automaticCrank and 1 or 0, 0)
        return
    end
end

function RMS_Breakdowns.cancelStarterCranking(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.activeEffects == nil then
        return
    end

    for _, effectId in ipairs({ "ENGINE_FAILURE", "ENGINE_HARD_START_MODIFIER", "GLOW_PLUG_HARD_START_MODIFIER" }) do
        local effect = spec.activeEffects[effectId]
        if effect ~= nil and effect.extraData ~= nil and effect.extraData.status == "CRANKING" then
            effect.extraData.status = "IDLE"
            effect.extraData.timer = 0
            effect.extraData.preCrankVoltageV = nil
            effect.extraData.automaticCrank = false
            RMS_EffectSyncEvent.send(vehicle, effectId, "IDLE", 0, 0, 0)
        end
    end

    syncStarterCrankingSample(vehicle)
end


-- ==========================================================
-- GEAR_SHIFT_FAILURE_CHANCE
RMS_Breakdowns.EffectApplicators.GEAR_SHIFT_FAILURE_CHANCE = {
    getEffectName = function()
        return "GEAR_SHIFT_FAILURE_CHANCE" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()

        if vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] == nil then
            vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = function(v, dt)
                
                if v:getIsMotorStarted() then
                    local spec = v.spec_RealisticMechanicalSystems           
                    local effect = spec.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
                    if effect and effect.value > 0 and effect.extraData.status == "FAILED" then
                        effect.extraData.timer = effect.extraData.timer + dt
                        if effect.extraData.timer > effect.extraData.duration then
                            effect.extraData.timer = 0
                            effect.extraData.status = "IDLE"
                        end
                    end
                end
            end
        end
    end,

    remove = function(vehicle, handler)

        local effectName = handler.getEffectName()
        if vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] ~= nil then
            vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = nil
        end
    end
}

if VehicleMotor ~= nil and VehicleMotor.shiftGear ~= nil then
    VehicleMotor.shiftGear = Utils.overwrittenFunction(VehicleMotor.shiftGear, function(self, superFunc, up)
        local vehicle = self.vehicle
        if vehicle ~= nil then
            local spec_rms = vehicle.spec_RealisticMechanicalSystems
            if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
                local effect = spec_rms.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
                if effect ~= nil and effect.value ~= nil then
                    if effect.extraData.status == "FAILED" then return end
                    if vehicle.isServer and math.random() < effect.value then
                        effect.extraData.status = "FAILED"
                        local sampleIndex = math.random(3)
                        RMS_SoundManager.playSample(spec_rms.samples["transmissionShiftFailed" .. sampleIndex])
                        RMS_EffectSyncEvent.send(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", "FAILED", 0, sampleIndex, 0)
                        return
                    end
                end
            end
        end
        return superFunc(self, up)
    end)
end

if VehicleMotor ~= nil and VehicleMotor.selectGear ~= nil then
    VehicleMotor.selectGear = Utils.overwrittenFunction(VehicleMotor.selectGear, function(self, superFunc, gearIndex, activation)
        local vehicle = self.vehicle
        if vehicle ~= nil then
            local spec_rms = vehicle.spec_RealisticMechanicalSystems
            if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
                local effect = spec_rms.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
                if effect ~= nil and effect.value ~= nil then
                    if effect.extraData.status == "FAILED" then return end
                    if activation then
                        if vehicle.isServer and math.random() < effect.value then
                            effect.extraData.status = "FAILED"
                            local sampleIndex = math.random(3)
                            RMS_SoundManager.playSample(spec_rms.samples["transmissionShiftFailed" .. sampleIndex])
                            RMS_EffectSyncEvent.send(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", "FAILED", 0, sampleIndex, 0)
                            return
                        end
                    end
                end
            end
        end
        return superFunc(self, gearIndex, activation)
    end)
end

if VehicleMotor ~= nil and VehicleMotor.updateGear ~= nil then
    VehicleMotor.updateGear = Utils.overwrittenFunction(VehicleMotor.updateGear, function(self, superFunc, acceleratorPedal, brakePedal, dt)
        local vehicle = self.vehicle
        local wasShifting = (self.gear == 0 and self.gearChangeTimer > 0)
        local adjAcceleratorPedal, adjBrakePedal = superFunc(self, acceleratorPedal, brakePedal, dt)
        local isShifting = (self.gear == 0 and self.gearChangeTimer > 0)

        if vehicle ~= nil and isShifting and not wasShifting then
            local spec_rms = vehicle.spec_RealisticMechanicalSystems
            if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
                local effect = spec_rms.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
                if effect ~= nil and effect.value ~= nil then
                    if vehicle.isServer and math.random() < effect.value then
                        effect.extraData.status = "FAILED"
                        effect.extraData.timer = 0

                        self.gearChangeTimer = effect.extraData.duration
                        self.autoGearChangeTimer = effect.extraData.duration

                        local sampleIndex = math.random(3)
                        RMS_SoundManager.playSample(spec_rms.samples["transmissionShiftFailed" .. sampleIndex])
                        RMS_EffectSyncEvent.send(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", "FAILED", 0, sampleIndex, effect.extraData.duration)
                    end
                    if effect.value >= 1.0 then
                        self.targetGear = self.previousGear
                    end
                end
            end
        end

        return adjAcceleratorPedal, adjBrakePedal
    end)
end

-- ==========================================================
-- GEAR_REJECTION_CHANCE
RMS_Breakdowns.EffectApplicators.GEAR_REJECTION_CHANCE = {
    getEffectName = function() return "GEAR_REJECTION_CHANCE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)
            if v:getIsMotorStarted() then
                local effect = v.spec_RealisticMechanicalSystems.activeEffects.GEAR_REJECTION_CHANCE
                if effect and effect.value > 0 then
                    local motor = v:getMotor()
                    if effect.extraData.status == 'REJECTED' then
                        motor.targetGear = 0
                        effect.extraData.timer = effect.extraData.timer + dt
                        if v.isServer and effect.extraData.timer >= effect.extraData.duration then
                            effect.extraData.status = 'IDLE'
                            effect.extraData.timer = 0
                            local sampleIndex = math.random(3)
                            RMS_SoundManager.playSample(v.spec_RealisticMechanicalSystems.samples["transmissionShiftFailed" .. sampleIndex])
                            RMS_EffectSyncEvent.send(v, "GEAR_REJECTION_CHANCE", "IDLE", 0, sampleIndex)
                        end

                    elseif v.isServer and v:getMotorLoadPercentage() > 0.8 and effect.extraData.status == 'IDLE' then
                        if math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                            effect.extraData.status = 'REJECTED'
                            effect.extraData.timer = 0
                            if motor and motor.setGear then
                                motor:setGear(0, false)

                                RMS_EffectSyncEvent.send(v, "GEAR_REJECTION_CHANCE", "REJECTED", 0)
                                RMS_SoundManager.playSample(v.spec_RealisticMechanicalSystems.samples.gearDisengage1)
                                if v:getIsActiveForInput(true) then
                                    g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_gear_disengage_message", 3000)) 
                                end
                            end
                        end
                    end
                end
            end
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- ==========================================================
-- LIGHTS_FLICKER_CHANCE
RMS_Breakdowns.EffectApplicators.LIGHTS_FLICKER_CHANCE = {
    getEffectName = function()
        return "LIGHTS_FLICKER_CHANCE" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()

        local activeFunc = function(v, dt)
                if v:getIsMotorStarted() then
                    local spec = v.spec_RealisticMechanicalSystems
                    local effect = spec.activeEffects.LIGHTS_FLICKER_CHANCE
                    if effect and effect.value > 0 then
                        if v.spec_lights == nil then return end

                        if effect.extraData.status == 'FLICKING' and effect.extraData.timer < effect.extraData.duration then
                            effect.extraData.timer = effect.extraData.timer + dt
                            local maxMask = v.spec_lights.maxLightStateMask
                            local randomMask = math.random(0, maxMask)
                            v:setLightsTypesMask(randomMask, true, true)

                        elseif effect.extraData.status == 'FLICKING' and effect.extraData.timer > effect.extraData.duration then
                            effect.extraData.status = 'IDLE'
                            effect.extraData.timer = 0
                            v:setLightsTypesMask(effect.extraData.maskBackup, true, true)

                        elseif v.isServer and effect.extraData.status == 'IDLE' then
                            if math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                                effect.extraData.maskBackup = v:getLightsTypesMask()
                                if effect.extraData.maskBackup == 0 then return end
                                effect.extraData.status = 'FLICKING'

                                RMS_EffectSyncEvent.send(v, "LIGHTS_FLICKER_CHANCE", "FLICKING", 0, effect.extraData.maskBackup)

                            end
                        end
                    end
                end
            end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- =========================================================
-- EMPTY_EFFECT
RMS_Breakdowns.EffectApplicators.EMPTY_EFFECT = {
}

-- ==========================================================
function RMS_Breakdowns.getCanMotorRun(self, superFunc)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return superFunc(self)
    end

    if (spec and spec.activeEffects.ENGINE_FAILURE) then
        if not spec.activeEffects.ENGINE_FAILURE.extraData.starter then
            return false
        end
    elseif self:isUnderService() then
        if self:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText(self:getCurrentStatus()) .. " " .. g_i18n:getText("rms_breakdown_at_progress_message", 100)) 
        end
        return false
    end

    if RMS_Preheat.shouldBlockMotorRun(self) then
        return false
    end

    return superFunc(self)
end
