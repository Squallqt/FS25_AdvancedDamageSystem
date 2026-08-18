-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Runtime effects of the breakdowns, applied to the vehicle through engine function overrides
RMS_Breakdowns = {}

local log_dbg = RMS_Utils.createLogger("[RMS_BREAKDOWNS]")

local loggedHookErrors = {}

-- brake sound plays once per crossing of this speed, in km/h
local BRAKE_SOUND_SPEED_THRESHOLD = 15

---Reports a wrapped engine call failure once per distinct error
-- @param string context name of the wrapped call
-- @param any err error raised
local function log_hook_error(context, err)
    local key = context .. "|" .. tostring(err)
    if loggedHookErrors[key] then
        return
    end
    loggedHookErrors[key] = true
    Logging.error("[RMS_BREAKDOWNS] %s failed: %s", context, tostring(err))
end

source(g_currentModDirectory .. "scripts/core/RMS_BreakdownRegistry.lua")


RMS_Breakdowns.EffectApplicators = {}

---Registers the per frame function of an effect, keeping any already registered
-- @param table v vehicle
-- @param string effectName effect id
-- @param function func per frame function
local function addFuncToActive(v, effectName, func)
    if v.spec_RealisticMechanicalSystems.activeFunctions[effectName] == nil then
        v.spec_RealisticMechanicalSystems.activeFunctions[effectName] = func
    end
end

---Drops the per frame function of an effect
-- @param table v vehicle
-- @param string effectName effect id
local function removeFuncFromActive(v, effectName)
    if v.spec_RealisticMechanicalSystems.activeFunctions[effectName] ~= nil then
        v.spec_RealisticMechanicalSystems.activeFunctions[effectName] = nil
    end
end

---Returns the starter pitch offset, dropping as the pre crank voltage falls below 12.2 volts
-- @param float? preCrankVoltageV battery voltage before cranking
-- @return float offset pitch offset
local function getStarterCrankingPitchOffset(preCrankVoltageV)
    local resolvedVoltage = preCrankVoltageV or 12.2
    local t = math.clamp((12.2 - resolvedVoltage) / 0.5, 0, 1)
    return -0.25 * (t * t)
end

---Returns the effect currently cranking the starter, engine failure taking precedence
-- @param table? spec vehicle spec
-- @return table? effect cranking effect, nil when none cranks
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

---Tells whether the starter is being asked for, by the player or by the automatic crank
-- @param table? vehicle vehicle
-- @param table? effect cranking effect
-- @return boolean isActive true while the starter is requested
local function getIsStarterRequestActive(vehicle, effect)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and (spec.startButtonHeld == true
        or (effect ~= nil and effect.extraData ~= nil and effect.extraData.automaticCrank == true))
end

---Plays the starter sample while the engine cranks, pitched by the battery voltage
-- @param table? vehicle vehicle
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

---Plays the starter release sample once
-- @param table? spec vehicle spec
-- @param float? pitchOffset pitch offset
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

-- clears its own breakdown as soon as it is applied
RMS_Breakdowns.EffectApplicators.SELF_DISAPPEARING_BREAKDOWN_EFFECT = {
    apply = function(vehicle, effectData, handler)
        vehicle:removeBreakdown(effectData.extraData.breakdownId)
    end,

}

-- keeps the engine from running and cranks the starter without catching
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

-- forces the affected light types off
RMS_Breakdowns.EffectApplicators.LIGHTS_FAILURE = {
    apply = function(vehicle, effectData, handler)
        local currentLightMask = vehicle:getLightsTypesMask()
        if currentLightMask ~= 0 then
            vehicle:setLightsTypesMask(0, true, true)
        end
    end,

}

---Filters out the light types the lights failure effect disabled
-- @param table self vehicle
-- @param function superFunc super function
-- @param integer lightsTypesMask light types mask
-- @param boolean force force
-- @param boolean noEventSend no event send
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

---Picks the wheel a seizure acts on, reusing the cached one when it is still valid
-- @param table vehicle vehicle
-- @return table? wheelData target wheel data
local function getWheelSeizureTargetWheel(vehicle)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    local spec_wheels = vehicle.spec_wheels
    if spec_rms == nil or spec_wheels == nil or spec_wheels.wheels == nil then
        return nil
    end

    local wheels = spec_wheels.wheels

    ---Collects the runtime fields of a wheel into one table
    -- @param table? wheel wheel
    -- @return table? data wheel runtime data
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

    ---Tells whether a wheel carries a usable node and wheel shape
    -- @param table? wd wheel runtime data
    -- @return boolean isValid true when the wheel can be acted on
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
    ---Returns the local position of a wheel
    -- @param table wheelData wheel runtime data
    -- @return float positionX local x position
    -- @return float positionZ local z position
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

    ---Returns the first wheel matching a predicate
    -- @param function predicate test applied to each wheel
    -- @return table? wheelData matching wheel data
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

-- scales the brake force of the vehicle
RMS_Breakdowns.EffectApplicators.BRAKE_FORCE_MODIFIER = {
}

-- offsets the steering neutral point while keeping the full range
RMS_Breakdowns.EffectApplicators.STEERING_STATIC_BIAS_EFFECT = {
}

-- scales how much the steering input turns the wheels
RMS_Breakdowns.EffectApplicators.STEERING_SENSITIVITY_MODIFIER = {
}

-- drags one wheel without anchoring the vehicle
RMS_Breakdowns.EffectApplicators.WHEEL_SEIZURE_EFFECT = {
    remove = function(vehicle, handler)
        if vehicle.spec_RealisticMechanicalSystems ~= nil then
            vehicle.spec_RealisticMechanicalSystems.wheelSeizureTargetIndex = nil
        end
    end
}

-- cuts the throttle at random and drops the cruise control
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

---Applies the steering bias, the steering sensitivity and the wheel seizure to the physics step
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param float axisForward forward axis input
-- @param float axisSide side axis input
-- @param boolean doHandbrake handbrake input
-- @param float dt time since last call in ms
function RMS_Breakdowns.updateVehiclePhysics(vehicle, superFunc, axisForward, axisSide, doHandbrake, dt)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms == nil then
        return superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)
    end

    -- park brake anchors the machine and ignores the throttle
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

    if steeringSensitivityEffect ~= nil and steeringSensitivityEffect.value ~= nil then
        local value = math.max(tonumber(steeringSensitivityEffect.value) or 0, 0)
        local sensitivity = math.clamp(1 - value, 0.05, 1.0)
        axisSide = axisSide * sensitivity
    end

    if steeringStaticBiasEffect ~= nil and steeringStaticBiasEffect.value ~= nil then
        local value = math.abs(tonumber(steeringStaticBiasEffect.value) or 0)
        local leftBias = -math.clamp(value, 0, 1.0)
        local x = math.clamp(axisSide, -1.0, 1.0)

        -- neutral point shifts left while the endpoints stay at -1 and 1
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

-- scales the engine torque
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
                  
-- scales the fuel consumption
RMS_Breakdowns.EffectApplicators.FUEL_CONSUMPTION_MODIFIER = {
}

---Applies the fuel consumption modifier to the consumers of the vehicle
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
-- @param float accInput acceleration input
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

---Replaces the vanilla consumer update with the modified one
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param float accInput acceleration input
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

-- lets the transmission slip, converging on the effect value
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

-- lets the CVT slip
RMS_Breakdowns.EffectApplicators.CVT_SLIP_EFFECT = {

    remove = function(vehicle, handler)
        local motor = vehicle:getMotor()
        if motor ~= nil then
            motor:setExternalTorqueVirtualMultiplicator(1)
        end
    end
}

-- caps the CVT ratio
RMS_Breakdowns.EffectApplicators.CVT_MAX_RATIO_MODIFIER = {
}

-- convergence rate of the slip modifier, per second at full factor
local TRANSMISSION_SLIP_CONVERGENCE_PER_SECOND = 0.9
-- gap beyond which a frame contributes no elapsed time
local TRANSMISSION_SLIP_RESUME_GAP_SECONDS = 0.25

if VehicleMotor ~= nil and VehicleMotor.getMinMaxGearRatio ~= nil then
    VehicleMotor.getMinMaxGearRatio = Utils.overwrittenFunction(VehicleMotor.getMinMaxGearRatio, function(self, superFunc)
        local minRatio, maxRatio = superFunc(self)
        local vehicle = self.vehicle
        if vehicle == nil then return minRatio, maxRatio end

        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms == nil or spec_rms.activeEffects == nil then return minRatio, maxRatio end

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

        local cvtMaxEffect = spec_rms.activeEffects.CVT_MAX_RATIO_MODIFIER
        local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6 / 2), 1.0)
        if cvtMaxEffect ~= nil and cvtMaxEffect.value ~= nil and self.minForwardGearRatio ~= nil and not isSliping and speedFactor > 0.5 then
            local value = tonumber(cvtMaxEffect.value) or 0
            minRatio = minRatio + minRatio * value * speedFactor
        end

        local pressureDropEffect = spec_rms.activeEffects.CVT_PRESSURE_DROP_CHANCE
        if pressureDropEffect ~= nil and pressureDropEffect.extraData ~= nil 
            and pressureDropEffect.extraData.status == "PROGRESS"
            and (pressureDropEffect.extraData.timer or 0) > 0 then
            minRatio = minRatio * 1.5
        end

        return minRatio, maxRatio
    end)
end

-- delays and roughens the powershift engagement
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


---Tells whether a folded implement blocks the hydraulic drift
-- @param table? implement implement
-- @return boolean isBlocked true while the drift must not run
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

---Bypasses the implement speed limit so the forced drop can run
-- @param table? implement implement
-- @param boolean enabled true to bypass the limit
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

---Puts the implement speed limit back
-- @param table? implement implement
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

---Returns the lifted mass over the hydraulic capacity of the vehicle
-- @param table vehicle vehicle
-- @param float mass lifted mass
-- @return float ratio mass ratio
local function getHydraulicMassRatio(vehicle, mass)
    return math.clamp(mass / math.max(vehicle:getTotalMass(true), 0.01), 0, 1)
end

---Picks the hydraulic function the erratic effect acts on
-- @param table vehicle vehicle
-- @param integer? targetIndex hydraulic function index
local function setHydraulicErraticTarget(vehicle, targetIndex)
    local currentIndex = 0
    local visited = {}

    ---Walks the implement chain looking for a hydraulic function to act on
    -- @param table? childVehicle vehicle or implement
    local function scanVehicle(childVehicle)
        if childVehicle == nil or visited[childVehicle] then
            return
        end
        visited[childVehicle] = true

        local attacherSpec = childVehicle.spec_attacherJoints
        if attacherSpec ~= nil then
            for _, implementData in pairs(attacherSpec.attachedImplements or {}) do
                local jointDesc = attacherSpec.attacherJoints[implementData.jointDescIndex]
                if jointDesc ~= nil then
                    jointDesc.rmsHydraulicErraticTarget = false
                    if RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                        currentIndex = currentIndex + 1
                        jointDesc.rmsHydraulicErraticTarget = currentIndex == targetIndex
                    end
                end
            end
        end

        if childVehicle.spec_cylindered ~= nil then
            for _, tool in ipairs(childVehicle.spec_cylindered.movingTools) do
                tool.rmsHydraulicErraticTarget = false
                if RMS_Utils.getIsHydraulicMovingTool(tool) and (tool.rotSpeed ~= nil or tool.transSpeed ~= nil) then
                    currentIndex = currentIndex + 1
                    tool.rmsHydraulicErraticTarget = currentIndex == targetIndex
                end
            end
        end

        local children = childVehicle.getChildVehicles ~= nil and childVehicle:getChildVehicles() or {}
        for _, nestedVehicle in pairs(children) do
            scanVehicle(nestedVehicle)
        end
    end

    scanVehicle(vehicle)

    return currentIndex
end

-- slows the hydraulic movement
RMS_Breakdowns.EffectApplicators.HYDRAULIC_SPEED_MODIFIER = {

}

-- makes one hydraulic function move erratically
RMS_Breakdowns.EffectApplicators.HYDRAULIC_FUNCTION_ERRATIC_EFFECT = {
    getEffectName = function()
        return "HYDRAULIC_FUNCTION_ERRATIC_EFFECT"
    end,

    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)
            local spec = v.spec_RealisticMechanicalSystems
            local effect = spec.activeEffects[effectName]
            local breakdown = spec.activeBreakdowns.HYDRAULIC_SPOOL_VALVE_MALFUNCTION
            local childVehicleHash = v:getChildVehicleHash()

            if effect.extraData.childVehicleHash ~= childVehicleHash or breakdown.effectTargetIndex == 0 then
                local targetCount = setHydraulicErraticTarget(v, breakdown.effectTargetIndex)
                local previousTargetIndex = breakdown.effectTargetIndex
                if breakdown.effectTargetIndex == 0 and targetCount > 0 and v.isServer then
                    breakdown.effectTargetIndex = math.random(1, targetCount)
                    setHydraulicErraticTarget(v, breakdown.effectTargetIndex)
                end
                effect.extraData.childVehicleHash = childVehicleHash

                if previousTargetIndex ~= breakdown.effectTargetIndex then
                    RealisticMechanicalSystems.raiseRMSDirty(v, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
                end
            end
        end

        addFuncToActive(vehicle, effectName, activeFunc)
        activeFunc(vehicle, 0)
    end,

    remove = function(vehicle, handler)
        setHydraulicErraticTarget(vehicle, 0)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- lets a raised implement drop slowly on its own
RMS_Breakdowns.EffectApplicators.HYDRAULIC_HOLD_DRIFT_EFFECT = {
    getEffectName = function()
        return "HYDRAULIC_HOLD_DRIFT_EFFECT"
    end,

    apply = function(vehicle, effectData, handler)
        local activeFunc = function(v, dt) 
            if not v.isServer then
                return
            end

            local rootSpec = v.spec_RealisticMechanicalSystems
            local activeEffect = rootSpec.activeEffects.HYDRAULIC_HOLD_DRIFT_EFFECT
            local breakdown = rootSpec.activeBreakdowns.HYDRAULIC_CYLINDER_INTERNAL_LEAK
            local targetCount = 0
            local attacherSpec = v.spec_attacherJoints
            if attacherSpec == nil or breakdown == nil then
                return
            end

            for _, implementData in pairs(attacherSpec.attachedImplements or {}) do
                local jointDesc = attacherSpec.attacherJoints[implementData.jointDescIndex]
                if jointDesc ~= nil and RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                    targetCount = targetCount + 1
                end
            end

            if targetCount > 0 and (breakdown.effectTargetIndex <= 0 or breakdown.effectTargetIndex > targetCount) then
                breakdown.effectTargetIndex = math.random(1, targetCount)
                RealisticMechanicalSystems.raiseRMSDirty(v, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
            end

            if v.spec_attacherJoints and v.spec_attacherJoints.attachedImplements and next(v.spec_attacherJoints.attachedImplements) ~= nil then
                local currentTargetIndex = 0
                for _, implementData in pairs(v.spec_attacherJoints.attachedImplements) do
                    if implementData.object ~= nil then
                        local implement = implementData.object
                        local jointDescIndex = implementData.jointDescIndex
                        local jointDesc = v.spec_attacherJoints.attacherJoints[jointDescIndex]
                        if jointDesc ~= nil and RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                            currentTargetIndex = currentTargetIndex + 1
                            local isTarget = currentTargetIndex == breakdown.effectTargetIndex
                            local liftedMass = rootSpec.hydraulicLiftMassByJoint[jointDesc] or 0
                            local loadMassRatio = getHydraulicMassRatio(v, liftedMass)
                            local canDriftUnderLoad = isTarget and loadMassRatio > 0
                            local driftBlockedByFold = isHydraulicHoldDriftBlockedByFold(implement)
                            local isLowered = implement:getIsLowered()
                            -- auto drift marker cleared once the movement finished or the player raised the implement
                            if jointDesc.rmsHoldDriftForced == true then
                                if not canDriftUnderLoad or driftBlockedByFold or (isLowered and not jointDesc.isMoving) or jointDesc.moveDown == false then
                                    jointDesc.rmsHoldDriftForced = false
                                end
                            end

                            -- forced slow drop only from a raised idle state
                            if canDriftUnderLoad and not driftBlockedByFold and not isLowered and not jointDesc.isMoving and jointDesc.moveDown == false then
                                jointDesc.rmsHoldDriftForced = true
                                v:setJointMoveDown(jointDescIndex, true, false)
                            end

                            local bypassWorkSpeedLimit = isTarget and jointDesc.rmsHoldDriftForced == true and jointDesc.moveDown == true and jointDesc.isMoving == true and not driftBlockedByFold
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

---Slows the attacher joint movement by the hydraulic effects
-- @param table self vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param any ... further arguments
function RMS_Breakdowns.applyHydraulicDamageToAttacher(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = self.spec_attacherJoints

    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local hydraulicHoldEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_HOLD_DRIFT_EFFECT
    local erraticEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_FUNCTION_ERRATIC_EFFECT
    local hydraulicModifier = (hydraulicEffect and hydraulicEffect.value) or 0
    local erraticModifier = (erraticEffect and erraticEffect.value) or 0
    local hydraulicHoldModifier = 0
    if hydraulicHoldEffect ~= nil then
        local loadMassRatio = getHydraulicMassRatio(rootVehicle, rootVehicle.spec_RealisticMechanicalSystems.liftedMass)
        if loadMassRatio > 0 then
            hydraulicHoldModifier = hydraulicHoldEffect.value * loadMassRatio
        end
    end
    
    if hydraulicModifier == 0 and hydraulicHoldModifier == 0 and erraticModifier == 0 then
        return superFunc(self, dt, ...)
    end

    local raisePerformance = math.max(0, 1.0 + hydraulicModifier)
    local holdDriftPerformance = math.max(tonumber(hydraulicHoldModifier) or 0, 0.01)
    local erraticPerformance = math.max(0.05, 1.0 + erraticModifier)
    local erraticPhaseActive = math.floor(g_currentMission.time / RMS_Config.CORE_UPDATE_DELAY) % 2 == 0
    local originalMoveTimes = {}

    for _, implement in ipairs(spec.attachedImplements) do
        if implement.object ~= nil then
            local jointDesc = spec.attacherJoints[implement.jointDescIndex]

            if not RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                jointDesc = nil
            end

            if jointDesc ~= nil then
                originalMoveTimes[jointDesc] = jointDesc.moveDefaultTime
            end

            -- raising the implement drops the forced hold drift in the same tick
            if jointDesc ~= nil and jointDesc.rmsHoldDriftForced == true and jointDesc.moveDown == false then
                jointDesc.rmsHoldDriftForced = false
            end

            if jointDesc ~= nil and jointDesc.rmsHydraulicErraticTarget == true and erraticModifier ~= 0 and not erraticPhaseActive then
                jointDesc.moveDefaultTime = math.huge
            elseif jointDesc ~= nil and jointDesc.moveDown == false and hydraulicModifier ~= 0 then
                jointDesc.moveDefaultTime = raisePerformance > 0 and originalMoveTimes[jointDesc] / raisePerformance or math.huge
            elseif jointDesc ~= nil and jointDesc.moveDown == true and jointDesc.rmsHoldDriftForced == true and hydraulicHoldModifier > 0 then
                jointDesc.moveDefaultTime = originalMoveTimes[jointDesc] / holdDriftPerformance
            elseif jointDesc ~= nil then
                jointDesc.moveDefaultTime = originalMoveTimes[jointDesc]
            end
        end
    end

    local success, result = pcall(superFunc, self, dt, ...)

    for _, implement in ipairs(spec.attachedImplements) do
        if implement.object ~= nil then
            local jointDesc = spec.attacherJoints[implement.jointDescIndex]
            
            if jointDesc ~= nil and originalMoveTimes[jointDesc] ~= nil then
                jointDesc.moveDefaultTime = originalMoveTimes[jointDesc]
            end
        end
    end

    if not success then
        log_hook_error("AttacherJoints.onUpdateTick", result)
        return
    end

    return result
end


---Slows the cylindered part movement by the hydraulic effects
-- @param table self vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param any ... further arguments
function RMS_Breakdowns.applyHydraulicDamageToCylindered(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = self.spec_cylindered

    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local erraticEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_FUNCTION_ERRATIC_EFFECT
    local hydraulicModifier = (hydraulicEffect and hydraulicEffect.value) or 0
    local erraticModifier = (erraticEffect and erraticEffect.value) or 0
    if hydraulicModifier == 0 and erraticModifier == 0 then
        return superFunc(self, dt, ...)
    end

    local performance = math.max(0, 1.0 + hydraulicModifier)
    local erraticPerformance = math.max(0.05, 1.0 + erraticModifier)
    local erraticPhaseActive = math.floor(g_currentMission.time / RMS_Config.CORE_UPDATE_DELAY) % 2 == 0
    local originalSpeeds = {}

    for _, tool in ipairs(spec.movingTools) do
        if RMS_Utils.getIsHydraulicMovingTool(tool) then
            originalSpeeds[tool] = {
                rotSpeed = tool.rotSpeed,
                transSpeed = tool.transSpeed,
                animSpeed = tool.animSpeed
            }
        end
        
        if RMS_Utils.getIsHydraulicMovingTool(tool) and tool.rotSpeed ~= nil then
            local toolPerformance = performance
            if tool.rmsHydraulicErraticTarget == true then
                toolPerformance = toolPerformance * (erraticPhaseActive and erraticPerformance or 0)
            end
            tool.rotSpeed = originalSpeeds[tool].rotSpeed * toolPerformance
        end
        if RMS_Utils.getIsHydraulicMovingTool(tool) and tool.transSpeed ~= nil then
            local toolPerformance = performance
            if tool.rmsHydraulicErraticTarget == true then
                toolPerformance = toolPerformance * (erraticPhaseActive and erraticPerformance or 0)
            end
            tool.transSpeed = originalSpeeds[tool].transSpeed * toolPerformance
        end
        if RMS_Utils.getIsHydraulicMovingTool(tool) and tool.animSpeed ~= nil then
            tool.animSpeed = originalSpeeds[tool].animSpeed * performance
        end
    end

    local success, result = pcall(superFunc, self, dt, ...)

    for _, tool in ipairs(spec.movingTools) do
        if originalSpeeds[tool] ~= nil then
            if tool.rotSpeed ~= nil then
                tool.rotSpeed = originalSpeeds[tool].rotSpeed
            end
            if tool.transSpeed ~= nil then
                tool.transSpeed = originalSpeeds[tool].transSpeed
            end
            if tool.animSpeed ~= nil then
                tool.animSpeed = originalSpeeds[tool].animSpeed
            end
        end
    end

    if not success then
        log_hook_error("Cylindered.onUpdate", result)
        return
    end

    return result
end

---Slows the attacher joint control movement by the hydraulic effects
-- @param table self vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param any ... further arguments
function RMS_Breakdowns.applyHydraulicDamageToAttacherJointControl(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local effect = rootVehicle.spec_RealisticMechanicalSystems
        and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local modifier = effect ~= nil and (tonumber(effect.value) or 0) or 0
    local spec = self.spec_attacherJointControl
    local jointDesc = spec ~= nil and spec.jointDesc or nil
    local originalMoveTime = jointDesc ~= nil and tonumber(jointDesc.moveTime) or nil

    if modifier == 0 or originalMoveTime == nil then
        return superFunc(self, dt, ...)
    end

    local performance = math.max(0, 1 + modifier)
    jointDesc.moveTime = performance > 0 and originalMoveTime / performance or math.huge
    local success, result = pcall(superFunc, self, dt, ...)
    jointDesc.moveTime = originalMoveTime

    if not success then
        log_hook_error("AttacherJointControl.onUpdate", result)
        return
    end

    return result
end

---Slows the hydraulic hammer by the hydraulic effects
-- @param table self vehicle
-- @param function superFunc super function
-- @param entityId actorId actor id
-- @param float x hit x position
-- @param float y hit y position
-- @param float z hit z position
-- @param float distance hit distance
-- @param float nx hit normal x
-- @param float ny hit normal y
-- @param float nz hit normal z
-- @param integer subShapeIndex sub shape index
-- @param entityId shapeId shape id
-- @param boolean isLast true on the last hit
function RMS_Breakdowns.applyHydraulicDamageToHammer(self, superFunc, actorId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    local rootVehicle = self:getRootVehicle()
    local effect = rootVehicle.spec_RealisticMechanicalSystems
        and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local modifier = effect ~= nil and (tonumber(effect.value) or 0) or 0
    if modifier == 0 then
        return superFunc(self, actorId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    end

    local performance = math.max(0, 1 + modifier)
    if performance <= 0 then
        return false
    end

    local workNode = self.spec_hydraulicHammer.workNode
    local originalMin = workNode.hitIntervalMin
    local originalMax = workNode.hitIntervalMax
    workNode.hitIntervalMin = math.ceil(originalMin / performance)
    workNode.hitIntervalMax = math.ceil(originalMax / performance)
    local success, result = pcall(superFunc, self, actorId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    workNode.hitIntervalMin = originalMin
    workNode.hitIntervalMax = originalMax

    if not success then
        log_hook_error("HydraulicHammer.hydraulicHammerRaycastCallback", result)
        return false
    end

    return result
end


do
    if not RMS_Breakdowns._hydraulicSpeedHooksInstalled then
        local hydraulicSpeedHookDefs = {
            { objectName = "AttacherJoints", field = "onUpdateTick", wrapperName = "applyHydraulicDamageToAttacher" },
            { objectName = "Cylindered", field = "onUpdate", wrapperName = "applyHydraulicDamageToCylindered" },
            { objectName = "AttacherJointControl", field = "onUpdate", wrapperName = "applyHydraulicDamageToAttacherJointControl" },
            { objectName = "HydraulicHammer", field = "hydraulicHammerRaycastCallback", wrapperName = "applyHydraulicDamageToHammer" }
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

-- caps the vehicle speed
RMS_Breakdowns.EffectApplicators.MAX_SPEED_MODIFIER = {

}

---Lowers the vehicle speed limit by the maximum speed modifier
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param boolean onlyIfWorking only if working
-- @return float speedLimit speed limit
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

-- scales the condition wear rate
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

-- scales the service wear rate
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

-- adds heat to the engine thermal model
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

-- adds heat to the transmission thermal model
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

-- adds heat to the hydraulic circuit
RMS_Breakdowns.EffectApplicators.HYDRAULIC_HEAT_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraHydraulicHeat = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraHydraulicHeat = 0
    end
}

-- lowers the engine thermostat health
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

-- lowers the radiator health
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

-- lowers the battery health
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

-- lowers the alternator health
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

-- lowers the fan clutch health
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

-- sticks the engine thermostat at a fixed opening
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

-- lowers the transmission thermostat health
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

-- sticks the transmission thermostat at a fixed opening
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

---Swings the idle rpm while the hunting effect runs, and restores it afterwards
-- @param table motor vehicle motor
-- @param table effectData effect data
-- @param float dt time since last call in ms
-- @param float rpmBackup idle rpm before the effect
-- @param boolean shouldHunt true while the rpm must swing
-- @param boolean allowRestore true to restore the idle rpm
-- @param boolean resetWhenInactive true to clear the state once inactive
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

-- swings the idle rpm up and down
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

-- raises the idle rpm while the engine is cold
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

-- adds resistance to the electrical circuit
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




---Stops a noise sample and clears its offsets
-- @param table? sample audio sample
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

---Eases a noise gate toward its target
-- @param table spec vehicle spec
-- @param string effectName effect id
-- @param float targetGate target gate value
-- @param float dt time since last call in ms
-- @return float gate current gate value
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

---Builds an effect applicator that plays one engine noise sample through a gate
-- @param string effectName effect id
-- @param string sampleName audio sample name
-- @param string gateMode how the gate follows the engine state
-- @return table applicator effect applicator
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
                local ptoData = nil

                if gateMode == "pto" then
                    ptoData = RMS_Utils.getConnectedPtoData(v)
                    local ptoRpm = math.max(tonumber(ptoData.rpm) or 0, 0)
                    local ptoMotorRpm = ptoRpm * motor:getPtoMotorRpmRatio()
                    rpmN = math.clamp((ptoMotorRpm - minRpm) / (maxRpm - minRpm), 0, 1)
                end

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
                elseif gateMode == "pto" then
                    local targetGate = ptoData ~= nil and ptoData.isActive and (tonumber(ptoData.rpm) or 0) > 0 and 1 or 0
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, targetGate, dt)
                    baseVolumeScale = baseVolumeScale * gate
                end

                if baseVolumeScale <= 0.02 then
                    if (gateMode == "boost" or gateMode == "speed" or gateMode == "pto") and gate > 0.001 then
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
RMS_Breakdowns.EffectApplicators.PTO_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("PTO_BEARING_NOISE_EFFECT", "ptoBearingNoise", "pto")


-- drops the CVT pressure at random
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

-- stalls the engine at random and warns the driver
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

-- disengages the PTO at random
RMS_Breakdowns.EffectApplicators.PTO_AUTO_DISENGAGE_CHANCE = {
    getEffectName = function() return "PTO_AUTO_DISENGAGE_CHANCE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()

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
                if v.isServer then
                    RMS_Utils.setConnectedPtoConsumersTurnedOn(v, false)
                elseif v:getIsActiveForInput(true) then
                    g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_pto_auto_disengage_message"), 4000)
                end
                effect.extraData.status = "IDLE"
                return
            end

            if not v.isServer then
                return
            end

            if not RMS_Utils.getConnectedPtoData(v).isActive then
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

-- keeps the PTO from running
RMS_Breakdowns.EffectApplicators.PTO_FAILURE = {
    getEffectName = function() return "PTO_FAILURE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)
            local effect = v.spec_RealisticMechanicalSystems.activeEffects[effectName]
            if v.isServer and effect ~= nil and (tonumber(effect.value) or 0) > 0 then
                RMS_Utils.setConnectedPtoConsumersTurnedOn(v, false)
            end
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

-- blocks the PTO engagement at random
RMS_Breakdowns.EffectApplicators.PTO_ENGAGEMENT_BLOCKED_CHANCE = {
    getEffectName = function() return "PTO_ENGAGEMENT_BLOCKED_CHANCE" end,
    apply = function(vehicle, effectData, handler)
    end,
    remove = function(vehicle, handler)
    end
}

---Blocks turning an implement on while the PTO engagement is blocked
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @return boolean canBeTurnedOn true when it may start
function RMS_Breakdowns.getCanBeTurnedOn(vehicle, superFunc)
    local canBeTurnedOn, warning = superFunc(vehicle)
    if not canBeTurnedOn or vehicle.getIsTurnedOn == nil or vehicle:getIsTurnedOn() then
        return canBeTurnedOn, warning
    end

    local rootVehicle = vehicle.rootVehicle
    local spec = rootVehicle ~= nil and rootVehicle.spec_RealisticMechanicalSystems or nil
    local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.PTO_ENGAGEMENT_BLOCKED_CHANCE or nil
    if effect == nil or spec.ptoEngagementAttempt ~= true then
        return canBeTurnedOn, warning
    end

    local ptoData = RMS_Utils.getConnectedPtoData(rootVehicle)
    if ptoData.connectedVehicles[vehicle] ~= true then
        return canBeTurnedOn, warning
    end

    if spec.ptoEngagementAttemptBlocked == nil then
        spec.ptoEngagementAttemptBlocked = math.random() < math.clamp(tonumber(effect.value) or 0, 0, 1)
    end

    if spec.ptoEngagementAttemptBlocked then
        if spec.ptoEngagementAttemptWarningShown ~= true
            and rootVehicle.getIsActiveForInput ~= nil
            and rootVehicle:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_pto_engagement_blocked_message"), 4000)
            spec.ptoEngagementAttemptWarningShown = true
        end
        return false, warning
    end

    return canBeTurnedOn, warning
end

---Runs a callback while the PTO engagement attempt is being counted
-- @param table vehicle vehicle
-- @param function callback function to run
local function runWithPtoEngagementAttempt(vehicle, callback)
    local rootVehicle = vehicle.rootVehicle
    local spec = rootVehicle ~= nil and rootVehicle.spec_RealisticMechanicalSystems or nil
    if spec ~= nil then
        spec.ptoEngagementAttempt = true
        spec.ptoEngagementAttemptBlocked = nil
        spec.ptoEngagementAttemptWarningShown = nil
    end
    local result = {callback()}
    if spec ~= nil then
        spec.ptoEngagementAttempt = false
        spec.ptoEngagementAttemptBlocked = nil
        spec.ptoEngagementAttemptWarningShown = nil
    end
    return unpack(result)
end

---Counts a PTO engagement attempt around the vanilla turn on action
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Breakdowns.actionEventTurnOn(vehicle, superFunc, actionName, inputValue, callbackState, isAnalog)
    return runWithPtoEngagementAttempt(vehicle, function()
        return superFunc(vehicle, actionName, inputValue, callbackState, isAnalog)
    end)
end

---Counts a PTO engagement attempt around the vanilla turn on all action
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Breakdowns.actionEventTurnOnAll(vehicle, superFunc, actionName, inputValue, callbackState, isAnalog)
    return runWithPtoEngagementAttempt(vehicle, function()
        return superFunc(vehicle, actionName, inputValue, callbackState, isAnalog)
    end)
end

---Counts a PTO engagement attempt around the action controller turn on
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param integer direction turn on direction
function RMS_Breakdowns.actionControllerTurnOnEvent(vehicle, superFunc, direction)
    return runWithPtoEngagementAttempt(vehicle, function()
        return superFunc(vehicle, direction)
    end)
end

if TurnOnVehicle ~= nil and TurnOnVehicle.getCanBeTurnedOn ~= nil then
    TurnOnVehicle.getCanBeTurnedOn = Utils.overwrittenFunction(TurnOnVehicle.getCanBeTurnedOn, RMS_Breakdowns.getCanBeTurnedOn)
end
if TurnOnVehicle ~= nil and TurnOnVehicle.actionEventTurnOn ~= nil then
    TurnOnVehicle.actionEventTurnOn = Utils.overwrittenFunction(TurnOnVehicle.actionEventTurnOn, RMS_Breakdowns.actionEventTurnOn)
end
if TurnOnVehicle ~= nil and TurnOnVehicle.actionEventTurnOnAll ~= nil then
    TurnOnVehicle.actionEventTurnOnAll = Utils.overwrittenFunction(TurnOnVehicle.actionEventTurnOnAll, RMS_Breakdowns.actionEventTurnOnAll)
end
if TurnOnVehicle ~= nil and TurnOnVehicle.actionControllerTurnOnEvent ~= nil then
    TurnOnVehicle.actionControllerTurnOnEvent = Utils.overwrittenFunction(TurnOnVehicle.actionControllerTurnOnEvent, RMS_Breakdowns.actionControllerTurnOnEvent)
end


---Rolls whether the engine catches, a cold engine and a weak battery both lowering the odds
-- @param float dt time since last call in ms
-- @param float value mean time between successful starts
-- @param float engTemp engine temperature in degrees
-- @param float? batV battery voltage
-- @return boolean started true when the engine catches
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

---Installs the hard start effect, cranking the starter until the engine catches or gives up
-- @param table vehicle vehicle
-- @param string effectName effect id
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

---Removes the hard start effect and its sounds
-- @param table vehicle vehicle
-- @param string effectName effect id
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

-- makes the engine crank before it catches
RMS_Breakdowns.EffectApplicators.ENGINE_HARD_START_MODIFIER = {
    getEffectName = function() return "ENGINE_HARD_START_MODIFIER" end,
    apply = function(vehicle, effectData, handler)
        applyHardStartModifier(vehicle, handler.getEffectName())
    end,
    remove = function(vehicle, handler)
        removeHardStartModifier(vehicle, handler.getEffectName())
    end
}

-- makes the engine crank before it catches after a failed preheat
RMS_Breakdowns.EffectApplicators.GLOW_PLUG_HARD_START_MODIFIER = {
    getEffectName = function() return "GLOW_PLUG_HARD_START_MODIFIER" end,
    apply = function(vehicle, effectData, handler)
        applyHardStartModifier(vehicle, handler.getEffectName())
    end,
    remove = function(vehicle, handler)
        removeHardStartModifier(vehicle, handler.getEffectName())
    end
}

---Tracks the start button state and forwards it to the server
-- @param table self vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
-- @param boolean isMouse true for a mouse input
-- @param integer deviceCategory input device category
-- @param any binding input binding
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

---Tells whether failing glow plugs block a cold start
-- @param table vehicle vehicle
-- @return boolean isBlocked true when the engine may not start
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

---Blocks the AI helper from starting a vehicle whose engine cannot run
-- @param table self vehicle
-- @param function superFunc super function
-- @param any ... further arguments
-- @return boolean canStart true when the helper may start it
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

---Runs the hard start sequence before letting the vanilla start go through
-- @param table self vehicle
-- @param function superFunc super function
-- @param boolean noEventSend no event send
-- @param boolean passed true once the start already went through
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

---Stops the starter and clears the cranking state
-- @param table? vehicle vehicle
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


-- makes a gear shift fail at random
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

-- throws the gearbox into neutral at random
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

-- flickers the lights at random
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

-- carries a value for other systems to read without acting on the vehicle
RMS_Breakdowns.EffectApplicators.EMPTY_EFFECT = {
}

---Blocks the engine from running while a fault or the preheat sequence forbids it
-- @param table self vehicle
-- @param function superFunc super function
-- @return boolean canRun true when the engine may run
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
