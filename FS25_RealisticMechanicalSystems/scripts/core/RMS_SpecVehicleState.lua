-- ==========================================================
--                      VEHICLE STATE
-- ==========================================================

local function updateActiveDraftStats(vehicle)  -- calculates the current active draft demand from attached implements
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return 0, 0
    end

    local result = {
        maxForce = 0,
        effectiveForceCap = 0,
        count = 0
    }
    local visited = {}

    local function collectDraftStats(rootVehicle)
        if rootVehicle == nil or visited[rootVehicle] then
            return
        end

        visited[rootVehicle] = true

        local attachedImplements = rootVehicle.getAttachedImplements ~= nil and rootVehicle:getAttachedImplements() or nil
        if attachedImplements == nil then
            return
        end

        for _, implement in pairs(attachedImplements) do
            local object = implement ~= nil and implement.object or nil
            if object ~= nil and not visited[object] then
                local powerConsumer = object.spec_powerConsumer
                if powerConsumer ~= nil then
                    local maxForce = tonumber(powerConsumer.maxForce) or 0
                    local multiplier = object.getPowerMultiplier ~= nil and (tonumber(object:getPowerMultiplier()) or 0) or 1
                    local speed = math.abs(tonumber(object.lastSpeedReal) or 0)
                    local movingDirection = tonumber(object.movingDirection) or 0
                    local forceDir = tonumber(powerConsumer.forceDir) or 0

                    local isActiveDraft = maxForce > 0
                        and multiplier > 0.001
                        and powerConsumer.forceNode ~= nil
                        and movingDirection == forceDir
                        and speed > 0.0001

                    if isActiveDraft then
                        result.maxForce = result.maxForce + maxForce
                        result.effectiveForceCap = result.effectiveForceCap + maxForce * multiplier
                        result.count = result.count + 1
                    end
                end

                collectDraftStats(object)
            end
        end
    end

    collectDraftStats(vehicle)

    spec.activeDraftMaxForce = result.maxForce 
    spec.activeDraftEffectiveForceCap = result.effectiveForceCap
end

local function updateAvgDynamicMotorLoadWindow(spec, dynamicMotorLoad, dt)
    if spec == nil then
        return 0
    end

    if not RMS_Config.DEBUG then
        spec._avgDynamicMotorLoadSamples = nil
        spec.avgDynamicMotorLoad = 0
        return 0
    end

    local durationMs = math.max(tonumber(dt) or 0, 1)
    local value = math.max(tonumber(dynamicMotorLoad) or 0, 0)
    local periodMs = 10000

    if type(spec._avgDynamicMotorLoadSamples) ~= "table" then
        spec._avgDynamicMotorLoadSamples = {}
    end

    local samples = spec._avgDynamicMotorLoadSamples
    table.insert(samples, {
        durationMs = durationMs,
        value = value
    })

    local totalDurationMs = 0
    local weightedSum = 0
    for _, sample in ipairs(samples) do
        local sampleDurationMs = math.max(tonumber(sample.durationMs) or 0, 0)
        local sampleValue = math.max(tonumber(sample.value) or 0, 0)
        totalDurationMs = totalDurationMs + sampleDurationMs
        weightedSum = weightedSum + sampleValue * sampleDurationMs
    end

    while #samples > 0 and totalDurationMs > periodMs do
        local oldest = samples[1]
        local oldestDurationMs = math.max(tonumber(oldest.durationMs) or 0, 0)
        local overflowMs = totalDurationMs - periodMs

        if oldestDurationMs <= overflowMs then
            totalDurationMs = totalDurationMs - oldestDurationMs
            weightedSum = weightedSum - (math.max(tonumber(oldest.value) or 0, 0) * oldestDurationMs)
            table.remove(samples, 1)
        else
            oldest.durationMs = oldestDurationMs - overflowMs
            totalDurationMs = totalDurationMs - overflowMs
            weightedSum = weightedSum - (math.max(tonumber(oldest.value) or 0, 0) * overflowMs)
        end
    end

    local avgValue = totalDurationMs > 0 and math.max(weightedSum / totalDurationMs, 0) or 0
    spec.avgDynamicMotorLoad = avgValue

    return avgValue
end

local function updateAvgSpeedWindow(spec, speed, dt)
    if spec == nil then
        return 0
    end

    if not RMS_Config.DEBUG then
        spec._avgSpeedSamples = nil
        spec.avgSpeed = 0
        return 0
    end

    local durationMs = math.max(tonumber(dt) or 0, 1)
    local value = math.max(tonumber(speed) or 0, 0)
    local periodMs = 10000

    if type(spec._avgSpeedSamples) ~= "table" then
        spec._avgSpeedSamples = {}
    end

    local samples = spec._avgSpeedSamples
    table.insert(samples, {
        durationMs = durationMs,
        value = value
    })

    local totalDurationMs = 0
    local weightedSum = 0
    for _, sample in ipairs(samples) do
        local sampleDurationMs = math.max(tonumber(sample.durationMs) or 0, 0)
        local sampleValue = math.max(tonumber(sample.value) or 0, 0)
        totalDurationMs = totalDurationMs + sampleDurationMs
        weightedSum = weightedSum + sampleValue * sampleDurationMs
    end

    while #samples > 0 and totalDurationMs > periodMs do
        local oldest = samples[1]
        local oldestDurationMs = math.max(tonumber(oldest.durationMs) or 0, 0)
        local overflowMs = totalDurationMs - periodMs

        if oldestDurationMs <= overflowMs then
            totalDurationMs = totalDurationMs - oldestDurationMs
            weightedSum = weightedSum - (math.max(tonumber(oldest.value) or 0, 0) * oldestDurationMs)
            table.remove(samples, 1)
        else
            oldest.durationMs = oldestDurationMs - overflowMs
            totalDurationMs = totalDurationMs - overflowMs
            weightedSum = weightedSum - (math.max(tonumber(oldest.value) or 0, 0) * overflowMs)
        end
    end

    local avgValue = totalDurationMs > 0 and math.max(weightedSum / totalDurationMs, 0) or 0
    spec.avgSpeed = avgValue

    return avgValue
end

local function updateDynamicMotorLoad(vehicle, dt) -- adjusts motor load with driveline vibration under active field work
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return 0
    end

    local motorLoad = RealisticMechanicalSystems.sanitizeNumber(vehicle:getMotorLoadPercentage(), 0, 0, 1.5)
    local hasMoreRealistic = g_modIsLoaded ~= nil and g_modIsLoaded["MoreRealistic"] == true

    if hasMoreRealistic then
        spec.dynamicMotorLoad = motorLoad
        updateAvgDynamicMotorLoadWindow(spec, motorLoad, dt)
        updateAvgSpeedWindow(spec, vehicle:getLastSpeed(), dt)
        return
    end

    local dynamicMotorLoad = motorLoad

    if vehicle:getIsOnField() then
        local isWorking = false
        if vehicle.spec_attacherJoints and vehicle.spec_attacherJoints.attachedImplements and next(vehicle.spec_attacherJoints.attachedImplements) ~= nil then
            for _, implementData in pairs(vehicle.spec_attacherJoints.attachedImplements) do
                if implementData.object ~= nil then
                    local implement = implementData.object
                    if implement:getIsLowered() then
                        isWorking = true
                    end
                end
            end
        end

        if isWorking then
            local motor = vehicle:getMotor()
            local peakPowerHp = RealisticMechanicalSystems.sanitizeNumber((motor.peakMotorPower or 0) * 1.36, 0, 0)
            local avgAbsDiffAcc = RealisticMechanicalSystems.sanitizeNumber(spec.avgAbsDiffAcc, 0, 0, 100)
            if peakPowerHp > 0.001 then
                local activeDraftEffectiveForceCap = RealisticMechanicalSystems.sanitizeNumber(spec.activeDraftEffectiveForceCap, 0, 0, 1000000)
                dynamicMotorLoad = math.min(motorLoad + math.min(avgAbsDiffAcc / 3, 0.15) * ((activeDraftEffectiveForceCap / peakPowerHp) / 0.15) ^ 2, 1.15)
            end
        end
    end

    spec.dynamicMotorLoad = RealisticMechanicalSystems.sanitizeNumber(dynamicMotorLoad, motorLoad, 0, 1.5)

    updateAvgDynamicMotorLoadWindow(spec, spec.dynamicMotorLoad or motorLoad, dt)
    updateAvgSpeedWindow(spec, vehicle:getLastSpeed(), dt)
end

local function updateAvgAbsDiffAccWindow(spec, motor, dt) -- Tracks the rolling average absolute differential acceleration over the last 500 ms
    if spec == nil or motor == nil then
        if spec ~= nil then
            spec.avgAbsDiffAcc = 0
        end
        return 0
    end

    local windowDurationMs = 500
    local diffAcc = math.abs(tonumber(motor.differentialRotAccelerationSmoothed) or 0)

    if spec._avgAbsDiffAccSamples == nil then
        spec._avgAbsDiffAccSamples = {}
    end

    local samples = spec._avgAbsDiffAccSamples

    for i = #samples, 1, -1 do
        local sample = samples[i]
        sample.ageMs = (tonumber(sample.ageMs) or 0) + (tonumber(dt) or 0)

        if sample.ageMs > windowDurationMs then
            table.remove(samples, i)
        end
    end

    table.insert(samples, {
        ageMs = 0,
        value = diffAcc
    })

    if #samples == 0 then
        spec.avgAbsDiffAcc = 0
        return 0
    end

    local sum = 0
    for i = 1, #samples do
        sum = sum + (tonumber(samples[i].value) or 0)
    end

    local avg = sum / #samples
    spec.avgAbsDiffAcc = avg
end

local function updateStarterState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return false
    end

    local engineHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.ENGINE_HARD_START_MODIFIER or nil
    local glowPlugHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER or nil
    local engineFailedEffect = spec.activeEffects ~= nil and spec.activeEffects.ENGINE_FAILURE or nil

    local isCranking = vehicle:getMotorState() == MotorState.STARTING or
        (engineHardStartEffect ~= nil and engineHardStartEffect.extraData ~= nil and engineHardStartEffect.extraData.status ~= nil and (engineHardStartEffect.extraData.status == "CRANKING" or engineHardStartEffect.extraData.status == "PASSED")) or 
        (glowPlugHardStartEffect ~= nil and glowPlugHardStartEffect.extraData ~= nil and glowPlugHardStartEffect.extraData.status ~= nil and (glowPlugHardStartEffect.extraData.status == "CRANKING" or glowPlugHardStartEffect.extraData.status == "PASSED")) or
        (engineFailedEffect ~= nil and engineFailedEffect.extraData ~= nil and engineFailedEffect.extraData.status ~= nil and engineFailedEffect.extraData.status == "CRANKING")

    spec.isCranking = isCranking
end

--- transmission
local function updateWheelSlip(vehicle)
    local spec_wheels = vehicle.spec_wheels
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end
    if spec_wheels == nil or spec_wheels.wheels == nil then
        spec.wheelSlipIntensity = 0
        spec._wheelSlipPreviousSample = 0
        spec._wheelSlipOlderSample = 0
        return
    end

    local brakeThreshold = tonumber(RMS_Config.CORE.CHASSIS_FACTOR_DATA.BRAKE_PEDAL_THRESHOLD) or 0.15
    if (tonumber(spec_wheels.brakePedal) or 0) > brakeThreshold then
        spec.wheelSlipIntensity = 0
        spec._wheelSlipPreviousSample = 0
        spec._wheelSlipOlderSample = 0
        return
    end

    local drivetrainState = RMS_Drivetrain ~= nil and RMS_Drivetrain.getState(vehicle) or nil
    local wheelSpeedSum = 0
    local drivenWheelCount = 0
    local function addWheelSpeed(wheelIndex)
        local wheel = spec_wheels.wheels[tonumber(wheelIndex)]
        local physicsWheel = wheel ~= nil and wheel.physics or nil
        if physicsWheel ~= nil and physicsWheel.wheelShapeCreated and physicsWheel.hasGroundContact then
            local radius = tonumber(physicsWheel.radius) or 0
            if radius > 0 then
                local axleSpeed = getWheelShapeAxleSpeed(wheel.node, physicsWheel.wheelShape)
                wheelSpeedSum = wheelSpeedSum + math.abs((tonumber(axleSpeed) or 0) * radius)
                drivenWheelCount = drivenWheelCount + 1
            end
        end
    end

    local layout = drivetrainState ~= nil and drivetrainState.layout or nil
    if RMS_Drivetrain ~= nil and RMS_Drivetrain.getIsAvailable(vehicle) and layout ~= nil then
        for _, wheelIndex in ipairs(layout.primaryWheelIndices) do
            addWheelSpeed(wheelIndex)
        end

        local fourWheelDrive = layout.centerIdx0 == nil
            or drivetrainState.driveMode == RMS_Drivetrain.MODE.FOUR_WD
            or (drivetrainState.driveMode == RMS_Drivetrain.MODE.AUTO and drivetrainState.autoEngaged)
        if fourWheelDrive then
            for _, wheelIndex in ipairs(layout.engageableWheelIndices) do
                addWheelSpeed(wheelIndex)
            end
        end
    else
        local differentials = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.differentials or nil
        if differentials ~= nil and next(differentials) ~= nil then
            local addedWheels = {}
            for _, differential in ipairs(differentials) do
                if differential.diffIndex1IsWheel then
                    local wheelIndex = tonumber(differential.diffIndex1)
                    if wheelIndex ~= nil and not addedWheels[wheelIndex] then
                        addedWheels[wheelIndex] = true
                        addWheelSpeed(wheelIndex)
                    end
                end
                if differential.diffIndex2IsWheel then
                    local wheelIndex = tonumber(differential.diffIndex2)
                    if wheelIndex ~= nil and not addedWheels[wheelIndex] then
                        addedWheels[wheelIndex] = true
                        addWheelSpeed(wheelIndex)
                    end
                end
            end
        else
            for wheelIndex, wheel in ipairs(spec_wheels.wheels) do
                local physicsWheel = wheel.physics
                if physicsWheel ~= nil and (tonumber(physicsWheel.driveMode) or 0) ~= 0 then
                    addWheelSpeed(wheelIndex)
                end
            end
        end
    end

    if drivenWheelCount == 0 then
        spec.wheelSlipIntensity = 0
        spec._wheelSlipPreviousSample = 0
        spec._wheelSlipOlderSample = 0
        return
    end
    local wheelSpeed = wheelSpeedSum / drivenWheelCount
    local groundSpeed = math.abs((tonumber(vehicle.lastSpeedReal) or 0) * 1000)
    local longitudinalSlipIntensity = 0
    -- Agricultural slip compares theoretical wheel speed with actual ground speed.
    if wheelSpeed > 0.0001 then
        longitudinalSlipIntensity = math.clamp((wheelSpeed - groundSpeed) / wheelSpeed, 0, 1)
    end

    -- Reject isolated physics spikes without altering sustained native slip.
    local previousSlip = spec._wheelSlipPreviousSample
    local olderSlip = spec._wheelSlipOlderSample
    spec._wheelSlipPreviousSample = longitudinalSlipIntensity
    spec._wheelSlipOlderSample = previousSlip
    spec.wheelSlipIntensity = longitudinalSlipIntensity + previousSlip + olderSlip
        - math.min(longitudinalSlipIntensity, previousSlip, olderSlip)
        - math.max(longitudinalSlipIntensity, previousSlip, olderSlip)
end

local function updateWheelGroundState(vehicle)
    local spec_wheels = vehicle.spec_wheels
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end
    if spec_wheels == nil or spec_wheels.wheels == nil then
        spec.avgTireGroundFrictionCoeff = 0
        spec.avgGroundSurfaceFactor = 0
        return
    end

    local frictionSum = 0
    local frictionCount = 0
    local surfaceFactorSum = 0
    local groundedWheelCount = 0
    for _, wheel in ipairs(spec_wheels.wheels) do
        local physics = wheel ~= nil and wheel.physics or nil
        if physics ~= nil and physics.hasGroundContact == true then
            groundedWheelCount = groundedWheelCount + 1

            local coeff = tonumber(physics.tireGroundFrictionCoeff)
            if coeff ~= nil and coeff > 0 then
                frictionSum = frictionSum + coeff
                frictionCount = frictionCount + 1
            end

            local densityType = physics.densityType or FieldGroundType.NONE
            local groundDepth = math.clamp(tonumber(physics.groundDepth) or 0, 0, 1)
            local groundType = WheelsUtil.getGroundType(
                densityType ~= FieldGroundType.NONE,
                physics.contact ~= WheelContactType.GROUND,
                groundDepth
            )
            if groundType == WheelsUtil.GROUND_ROAD then
                surfaceFactorSum = surfaceFactorSum + 1
            elseif groundType == WheelsUtil.GROUND_HARD_TERRAIN then
                surfaceFactorSum = surfaceFactorSum + (1 - groundDepth)
            end
        end
    end

    spec.avgTireGroundFrictionCoeff = frictionCount > 0 and frictionSum / frictionCount or 0
    spec.avgGroundSurfaceFactor = groundedWheelCount > 0 and surfaceFactorSum / groundedWheelCount or 0
end

--- hydraulic
local HYDRAULIC_LIFT_RATIO_DEADBAND = 0.05
local HYDRAULIC_LIFT_RATIO_INTERPOLATION_RATE = 1 / 1000

local function getWheelSupportState(vehicle)
    local supportWheelCount = 0
    local supportWheelLoad = 0

    if vehicle.spec_wheels ~= nil then
        for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
            if wheel.physics.hasGroundContact then
                supportWheelCount = supportWheelCount + 1
                supportWheelLoad = supportWheelLoad + wheel.physics:getTireLoad()
            end
        end
    end

    return supportWheelCount, supportWheelLoad
end

local function isTrailerJointType(jointTypeId)
    return jointTypeId == AttacherJoints.JOINTTYPE_TRAILER
        or jointTypeId == AttacherJoints.JOINTTYPE_TRAILERLOW
        or jointTypeId == AttacherJoints.JOINTTYPE_TRAILERCAR
        or jointTypeId == AttacherJoints.JOINTTYPE_SEMITRAILERCAR
end

local function getMoveState(vehicle, moveKey, jointDesc, nextMoveAlphaCache)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return false
    end
    local moveAlpha = jointDesc ~= nil and (jointDesc.moveAlpha or 0) or 0
    local prevMoveAlphaCache = spec.hydraulicsMoveAlphaCache or {}
    
    local prevMoveAlpha = prevMoveAlphaCache[moveKey]
    nextMoveAlphaCache[moveKey] = moveAlpha

    if prevMoveAlpha ~= nil then
        return math.abs(moveAlpha - prevMoveAlpha) > 0.05
    end

    local isMovingRaw = jointDesc ~= nil and jointDesc.isMoving == true
    return isMovingRaw and moveAlpha > 0.001 and moveAlpha < 0.999
end

local function getToolMotionFlags(vehicle)
    local isFoldMoving = false
    local isPlowRotationMoving = false
    local isCylinderedMoving = false

    if vehicle ~= nil and vehicle.spec_foldable ~= nil then
        isFoldMoving = math.abs(vehicle.spec_foldable.foldMoveDirection or 0) > 0.0001
    end

    if vehicle ~= nil and vehicle.spec_plow ~= nil and vehicle.spec_plow.rotationPart ~= nil and vehicle.spec_plow.rotationPart.turnAnimation ~= nil and vehicle.getIsAnimationPlaying ~= nil then
        isPlowRotationMoving = vehicle:getIsAnimationPlaying(vehicle.spec_plow.rotationPart.turnAnimation)
    end    

    if vehicle ~= nil and vehicle.spec_cylindered ~= nil then
        isCylinderedMoving = vehicle.spec_cylindered.movingToolNeedsSound == true
    end

    return isFoldMoving, isPlowRotationMoving, isCylinderedMoving
end

local function updateImplementChainState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return 0
    end

    spec.liftedMass = 0
    spec.operatingMass = 0
    spec.isImplementLifted = false
    spec.isImplementOperating = false
    spec.isImplementLowered = false

    local nextMoveAlphaCache = {}
    local nextLiftRatioCache = {}
    local implements = {}
    local liftBranches = {}
    local visited = {}
    local maxConnectedPtoAngleDeg = 0
    local hasConnectedPto = false
    local isPtoActive = false
    local ptoConnectionIsTrailerHitch = false
    local maxCutterArea = 0

    local function updatePtoActivityState(vehicleObj)
        local ptoActive = vehicleObj.getIsPowerTakeOffActive ~= nil and vehicleObj:getIsPowerTakeOffActive() or false
        local ptoConsuming = vehicleObj.getDoConsumePtoPower ~= nil and vehicleObj:getDoConsumePtoPower() or false
        local ptoRpm = vehicleObj.getPtoRpm ~= nil and (tonumber(vehicleObj:getPtoRpm()) or 0) or 0

        local ptoTorque = 0
        if PowerConsumer ~= nil and PowerConsumer.getTotalConsumedPtoTorque ~= nil then
            local ok, torqueValue = pcall(PowerConsumer.getTotalConsumedPtoTorque, vehicleObj, nil, nil, true)
            if ok then
                ptoTorque = tonumber(torqueValue) or 0
            end
        end

        if ptoActive or ptoConsuming or ptoRpm > 10 or ptoTorque > 0.001 then
            isPtoActive = true
        end
    end

    local function updateConnectedPtoState(parentObj, jointDescIndex, supportWheelCount)
        if parentObj ~= nil and parentObj.getOutputPowerTakeOffsByJointDescIndex ~= nil and jointDescIndex ~= nil then
            local outputs = parentObj:getOutputPowerTakeOffsByJointDescIndex(jointDescIndex) or {}
            for _, output in ipairs(outputs) do
                if output ~= nil and output.connectedInput ~= nil then
                    hasConnectedPto = true

                    -- towed implements have support wheels in ground contact; they use
                    -- wide-angle PTO shafts by design and must not trigger the sharp-angle penalty
                    if supportWheelCount > 0 then
                        ptoConnectionIsTrailerHitch = true
                    end

                    local inputPto = output.connectedInput
                    local outputNode = output.outputNode
                    local inputNode = inputPto ~= nil and inputPto.inputNode or nil

                    if outputNode ~= nil and inputNode ~= nil then
                        local outDirX, outDirY, outDirZ = localDirectionToWorld(outputNode, 0, 0, 1)
                        local inDirX, inDirY, inDirZ = localDirectionToWorld(inputNode, 0, 0, 1)
                        local angleDeg = nil

                        outDirX, outDirY, outDirZ = MathUtil.vector3Normalize(outDirX, outDirY, outDirZ)
                        inDirX, inDirY, inDirZ = MathUtil.vector3Normalize(inDirX, inDirY, inDirZ)

                        local outLen = MathUtil.vector3Length(outDirX, outDirY, outDirZ)
                        local inLen = MathUtil.vector3Length(inDirX, inDirY, inDirZ)
                        if outLen > 0.0001 and inLen > 0.0001 then
                            local cosine = MathUtil.dotProduct(outDirX, outDirY, outDirZ, inDirX, inDirY, inDirZ)
                            angleDeg = math.deg(math.acos(math.abs(math.clamp(cosine, -1.0, 1.0))))
                        end

                        if angleDeg == nil then
                            local x1, y1, z1 = getWorldTranslation(outputNode)
                            local x2, y2, z2 = getWorldTranslation(inputNode)
                            local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
                            local length = MathUtil.vector3Length(dx, dy, dz)
                            if length > 0.0001 then
                                local length2D = MathUtil.vector2Length(dx, dz)
                                local cosine = math.clamp(length2D / length, -1.0, 1.0)
                                angleDeg = math.deg(math.acos(cosine))
                            end
                        end

                        if angleDeg ~= nil then
                            maxConnectedPtoAngleDeg = math.max(maxConnectedPtoAngleDeg, angleDeg)
                        end
                    end
                end
            end
        end
    end

    local function collectImplementState(vehicleObj, parentObj, jointDesc, jointDescIndex, isHead, liftBranch)
        if vehicleObj == nil or visited[vehicleObj] then
            return
        end

        visited[vehicleObj] = true
        updatePtoActivityState(vehicleObj)

        local supportWheelCount, supportWheelLoad = getWheelSupportState(vehicleObj)
        local isMoving = false
        if isHead then
            if vehicleObj.spec_attacherJoints ~= nil and vehicleObj.spec_attacherJoints.attacherJoints ~= nil then
                for index, headJointDesc in pairs(vehicleObj.spec_attacherJoints.attacherJoints) do
                    isMoving = isMoving or getMoveState(vehicleObj, "__head:" .. tostring(index), headJointDesc, nextMoveAlphaCache)
                end
            end
        else
            local moveKey = string.format("%s:%s", tostring(vehicleObj), tostring(jointDescIndex or -1))
            isMoving = getMoveState(vehicle, moveKey, jointDesc, nextMoveAlphaCache)
            updateConnectedPtoState(parentObj, jointDescIndex, supportWheelCount)
        end

        local isFoldMoving, isPlowRotationMoving, isCylinderedMoving = getToolMotionFlags(vehicleObj)
        local isLowered = false

        if vehicleObj.getIsLowered ~= nil then
            isLowered = vehicleObj:getIsLowered(false)
        elseif jointDesc ~= nil then
            isLowered = jointDesc.moveDown == true
        end

        if vehicleObj.spec_cutter ~= nil and vehicleObj.spec_cutter.workAreaParameters ~= nil then
            maxCutterArea = math.max(maxCutterArea, tonumber(vehicleObj.spec_cutter.workAreaParameters.lastArea) or 0)
        end

        local implementData = {
            name = vehicleObj.getFullName ~= nil and vehicleObj:getFullName() or tostring(vehicleObj.configFileName or vehicleObj.customEnvironment or "implement"),
            mass = vehicleObj.getTotalMass ~= nil and (vehicleObj:getTotalMass(true) or 0) or 0,
            jointTypeId = isHead and 0 or (jointDesc ~= nil and jointDesc.jointType or nil),
            isLowered = isLowered,
            supportWheelCount = supportWheelCount,
            isMoving = isMoving,
            isFoldMoving = isFoldMoving,
            isPlowRotationMoving = isPlowRotationMoving,
            isCylinderedMoving = isCylinderedMoving,
            isHead = isHead == true
        }
        table.insert(implements, implementData)

        if not isHead then
            if parentObj == vehicle then
                liftBranch = {
                    root = vehicleObj,
                    mass = 0,
                    supportLoad = 0,
                    jointTypeId = implementData.jointTypeId,
                    isLowered = isLowered
                }
                table.insert(liftBranches, liftBranch)
            end

            if parentObj == vehicle or not vehicleObj.spec_attachable.isHardAttached then
                liftBranch.mass = liftBranch.mass + implementData.mass
            end
            liftBranch.supportLoad = liftBranch.supportLoad + supportWheelLoad
        end

        local attachedImplements = vehicleObj.getAttachedImplements ~= nil and vehicleObj:getAttachedImplements() or nil
        if attachedImplements ~= nil then
            for _, implementData in pairs(attachedImplements) do
                local childObj = implementData ~= nil and implementData.object or nil
                if childObj ~= nil then
                    local childJointDesc = nil
                    if vehicleObj.spec_attacherJoints ~= nil and vehicleObj.spec_attacherJoints.attacherJoints ~= nil then
                        childJointDesc = vehicleObj.spec_attacherJoints.attacherJoints[implementData.jointDescIndex]
                    end
                    collectImplementState(childObj, vehicleObj, childJointDesc, implementData.jointDescIndex, false, liftBranch)
                end
            end
        end
    end

    collectImplementState(vehicle, nil, nil, nil, true)
    
    for _, impl in ipairs(implements) do
        if impl.isLowered then
            spec.isImplementLowered = true
        end
        if (impl.isMoving and impl.jointTypeId ~= 0) or impl.isFoldMoving or impl.isPlowRotationMoving or (impl.isCylinderedMoving and not impl.isHead) then
            spec.isImplementOperating  = true
            local impMass = impl.supportWheelCount == 0 and impl.mass or impl.mass / 2
            if not impl.isHead then spec.operatingMass = spec.operatingMass + (impMass or 0) end
        end
    end

    local lockedHookLiftContainer = RMS_Utils.getLockedHookLiftContainer(vehicle)
    for _, branch in ipairs(liftBranches) do
        if not isTrailerJointType(branch.jointTypeId) and branch.root ~= lockedHookLiftContainer then
            local carriedRatio = branch.mass > 0 and math.clamp((branch.mass - branch.supportLoad) / branch.mass, 0, 1) or 0
            local liftRatioState = spec.hydraulicsLiftRatioCache[branch.root] or {
                interpolated = 0,
                applied = 0
            }

            local maxInterpolationStep = dt * HYDRAULIC_LIFT_RATIO_INTERPOLATION_RATE
            local interpolationDelta = math.clamp(
                carriedRatio - liftRatioState.interpolated,
                -maxInterpolationStep,
                maxInterpolationStep
            )
            liftRatioState.interpolated = math.clamp(
                liftRatioState.interpolated + interpolationDelta,
                0,
                1
            )

            if math.abs(liftRatioState.interpolated - liftRatioState.applied) > HYDRAULIC_LIFT_RATIO_DEADBAND then
                liftRatioState.applied = liftRatioState.interpolated
            end

            nextLiftRatioCache[branch.root] = liftRatioState

            if not branch.isLowered then
                spec.liftedMass = spec.liftedMass + branch.mass * liftRatioState.applied
                spec.isImplementLifted = spec.isImplementLifted or liftRatioState.applied > 0
            end
        end
    end

    local isOnField = vehicle.getIsOnField ~= nil and vehicle:getIsOnField() or false
    local lastSpeed = vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
    local isTurnedOn = vehicle.getIsTurnedOn == nil or vehicle:getIsTurnedOn()

    spec.hydraulicsMoveAlphaCache = nextMoveAlphaCache
    spec.hydraulicsLiftRatioCache = nextLiftRatioCache
    spec.maxConnectedPtoAngleDeg = maxConnectedPtoAngleDeg
    spec.hasConnectedPto = hasConnectedPto
    spec.isPtoActive = isPtoActive
    spec.ptoConnectionIsTrailerHitch = ptoConnectionIsTrailerHitch
    spec.implements = implements
    spec.isHarvesting = maxCutterArea > 0 and isOnField and lastSpeed >= 0.5 and isTurnedOn
end

--- chassis

local function updateChassisVibState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local vibState = spec.chassisVibState
    local prevSuspension = vibState.prevSuspension

    local speed = vehicle:getLastSpeed()
    local vibRaw = 0
    local vibWheelCount = 0
    local vibAvgDensityType = 0
    local vibSpeedFactor = 0
    local vibFieldMultiplier = 1

    if speed > 0.003 and vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels ~= nil then
        local sumSuspNorm = 0
        local countSuspNorm = 0
        local sumDensityType = 0
        local countDensityType = 0

        for wheelIndex, wheel in ipairs(vehicle.spec_wheels.wheels) do
            local runtimeWheel = wheel.physics or wheel
            local netInfo = runtimeWheel.netInfo or wheel.netInfo
            local suspTravel = tonumber(runtimeWheel.suspTravel or wheel.suspTravel) or 0
            local suspLength = tonumber((netInfo and netInfo.suspensionLength) or runtimeWheel.suspensionLength or wheel.suspensionLength) or 0
            local prevSuspLength = tonumber(prevSuspension[wheelIndex]) or suspLength
            local suspDelta = math.abs(suspLength - prevSuspLength)
            prevSuspension[wheelIndex] = suspLength

            local suspNorm = 0
            if suspTravel > 0.0001 then
                suspNorm = math.min(suspDelta / suspTravel, 3.0)
            end

            local hasGroundContact = false
            if wheel.physics ~= nil and wheel.physics.hasGroundContact ~= nil then
                hasGroundContact = wheel.physics.hasGroundContact == true
            elseif runtimeWheel.hasGroundContact ~= nil then
                hasGroundContact = runtimeWheel.hasGroundContact == true
            elseif wheel.hasGroundContact ~= nil then
                hasGroundContact = wheel.hasGroundContact == true
            end

            local densityType = tonumber(runtimeWheel.densityType or wheel.densityType) or -1

            if hasGroundContact then
                sumSuspNorm = sumSuspNorm + suspNorm
                countSuspNorm = countSuspNorm + 1
                if densityType >= 0 then
                    sumDensityType = sumDensityType + densityType
                    countDensityType = countDensityType + 1
                end
            end
        end

        vibRaw = countSuspNorm > 0 and (sumSuspNorm / countSuspNorm) or 0
        vibWheelCount = countSuspNorm
        vibAvgDensityType = countDensityType > 0 and (sumDensityType / countDensityType) or 0
        vibSpeedFactor = math.clamp(speed, 0.0, 50.0) / 50.0
        if vehicle.getIsOnField ~= nil and vehicle:getIsOnField() then
            vibFieldMultiplier = tonumber(RMS_Config.CORE.CHASSIS_FACTOR_DATA.VIB_FIELD_MULTIPLIER) or 1.3
        end
    end

    local vibSignal = vibRaw * vibSpeedFactor
    local alpha = dt / (300 + dt)

    vibState.raw = vibRaw
    vibState.signal = vibSignal
    vibState.wheelCount = vibWheelCount
    vibState.speedFactor = vibSpeedFactor
    vibState.avgDensityType = vibAvgDensityType
    vibState.fieldMultiplier = vibFieldMultiplier
    vibState.smoothed = vibState.smoothed + (vibSignal - vibState.smoothed) * alpha
end

local function updateChassisSteeringState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local steerState = spec.chassisSteerState
    local speed = vehicle:getLastSpeed()
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local steerSpeedThreshold = tonumber(C.STEER_LOAD_SPEED_THRESHOLD) or 4.0
    local steeringPosition = 0
    local drivableSpec = vehicle.spec_drivable
    local steeringInputMagnitude = math.abs(drivableSpec ~= nil and drivableSpec.axisSide or 0)

    if vehicle.rotatedTime ~= nil then
        steeringPosition = tonumber(vehicle.rotatedTime) or 0
    elseif drivableSpec ~= nil then
        steeringPosition = tonumber(drivableSpec.axisSide) or 0
    end

    local prevSteeringPosition = tonumber(steerState.prevPosition)
    local steerDeltaRate = 0
    local steerRateFactor = 0
    if prevSteeringPosition ~= nil then
        local dtSeconds = math.max((tonumber(dt) or 0) / 1000, 0.001)
        local steerDelta = math.abs(steeringPosition - prevSteeringPosition)
        steerDeltaRate = steerDelta / dtSeconds

        local rateDeadzone = math.max(tonumber(C.STEER_LOAD_RATE_DEADZONE) or 0.02, 0)
        local fullRate = math.max(tonumber(C.STEER_LOAD_RATE_FULL) or 0.60, rateDeadzone + 0.0001)
        local normalizedRate = math.clamp((steerDeltaRate - rateDeadzone) / math.max(fullRate - rateDeadzone, 0.0001), 0, 1)
        steerRateFactor = normalizedRate * normalizedRate
    end
    steerState.prevPosition = steeringPosition
    steerState.position = steeringPosition
    steerState.deltaRate = steerDeltaRate
    steerState.rateFactor = steerRateFactor

    local steeringMagnitude = 0
    local steerGroundContact = 0
    if vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels ~= nil then
        for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
            local physics = wheel.physics
            if physics ~= nil and RMS_Drivetrain.getIsWheelSteerable(wheel) then
                steeringMagnitude = math.max(steeringMagnitude, math.abs(tonumber(physics.steeringAngle) or 0))
            end

            local hasGroundContact = false
            if physics ~= nil and physics.hasGroundContact ~= nil then
                hasGroundContact = physics.hasGroundContact == true
            elseif wheel.hasGroundContact ~= nil then
                hasGroundContact = wheel.hasGroundContact == true
            end

            if hasGroundContact then
                steerGroundContact = 1
            end
        end
    end

    local articulatedAxis = vehicle.spec_articulatedAxis
    if articulatedAxis ~= nil and articulatedAxis.componentJoint ~= nil then
        steeringMagnitude = math.max(steeringMagnitude, math.abs(tonumber(articulatedAxis.curRot) or 0))
    end

    steerState.angleMagnitude = steeringMagnitude
    steerState.inputMagnitude = steeringInputMagnitude
    steerState.groundContact = steerGroundContact
    steerState.isLowSpeedActive = steerSpeedThreshold > 0 and speed <= steerSpeedThreshold
    steerState.isMoving = steerRateFactor > 0
end

local function updateChassisBrakingState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local brakeState = spec.chassisBrakeState
    brakeState.pedal = 0
    brakeState.massRatio = 0
    brakeState.trailerMass = 0
    brakeState.totalMass = 0
    brakeState.hpTrailerMassRatio = 1000
    brakeState.hpGrossMassRatio = 1000
    brakeState.isBraking = false
    brakeState.isBrakingByAxis = false

    local totalMass = vehicle:getTotalMass()
    local selfMass = vehicle:getTotalMass(true)
    local trailerMass = math.max(totalMass - selfMass, 0)
    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    local horsepower = math.max(((motor ~= nil and motor.peakMotorPower) or 0) * 1.36, 0.001)
    brakeState.trailerMass = trailerMass
    brakeState.totalMass = totalMass
    brakeState.hpTrailerMassRatio = horsepower / math.max(trailerMass, 0.01)
    brakeState.hpGrossMassRatio = horsepower / math.max(totalMass, 0.01)

    local drivable = vehicle.spec_drivable
    if drivable == nil or vehicle.spec_wheels == nil then
        return
    end

    local brakePedalRaw = tonumber(vehicle.spec_wheels.brakePedal) or 0
    local axisForward = drivable.axisForward
    local movingDirection = tonumber(vehicle.movingDirection) or 0
    local directionMode = vehicle.getDirectionChangeMode ~= nil and vehicle:getDirectionChangeMode() or 1
    local isBrakingByAxis = false

    if directionMode == 2 then
        isBrakingByAxis = axisForward < -0.01
    else
        isBrakingByAxis = movingDirection ~= 0 and axisForward ~= 0 and math.sign(movingDirection) ~= math.sign(axisForward)
    end

    local brakePedalThreshold = tonumber(RMS_Config.CORE.CHASSIS_FACTOR_DATA.BRAKE_PEDAL_THRESHOLD) or 0.15
    local brakePedal = math.clamp(brakePedalRaw, 0, 1)
    local isBraking = isBrakingByAxis or brakePedal > brakePedalThreshold

    local ownMass = vehicle:getTotalMass(true)
    local totalMass = vehicle:getTotalMass()
    local brakeMassRatio = ownMass > 0 and math.max(totalMass / ownMass, 0) or 0

    brakeState.pedal = brakePedal
    brakeState.massRatio = brakeMassRatio
    brakeState.isBraking = isBraking
    brakeState.isBrakingByAxis = isBrakingByAxis
end

local function updateFuelState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local fuelState = spec.fuelState

    local function resolveFuelLevel()
        local fuelFillUnit = nil
        if vehicle.getConsumerFillUnitIndex ~= nil and FillType ~= nil and FillType.DIESEL ~= nil then
            fuelFillUnit = vehicle:getConsumerFillUnitIndex(FillType.DIESEL)
        end

        if type(fuelFillUnit) == "table" then
            fuelFillUnit = tonumber(fuelFillUnit.fillUnitIndex or fuelFillUnit.index or fuelFillUnit[1])
        end

        local dieselType = FillType ~= nil and FillType.DIESEL or nil
        local methaneType = FillType ~= nil and FillType.METHANE or nil
        local electricType = FillType ~= nil and FillType.ELECTRICCHARGE or nil

        if fuelFillUnit == nil and vehicle.spec_motorized ~= nil and vehicle.spec_motorized.consumers ~= nil then
            for _, consumer in pairs(vehicle.spec_motorized.consumers) do
                if consumer ~= nil and consumer.fillUnitIndex ~= nil then
                    local fillType = consumer.fillType
                    if fillType == dieselType or fillType == methaneType or fillType == electricType then
                        fuelFillUnit = consumer.fillUnitIndex
                        break
                    end
                end
            end
        end

        if fuelFillUnit ~= nil then
            local fuelLiters = tonumber(vehicle:getFillUnitFillLevel(fuelFillUnit)) or 0
            local fuelCapacity = tonumber(vehicle:getFillUnitCapacity(fuelFillUnit)) or 0
            return fuelCapacity > 0 and (fuelLiters / fuelCapacity) or 0
        end

        return 0
    end

    local function resolveFuelUsageRatio()
        local motorizedSpec = vehicle.spec_motorized
        if motorizedSpec == nil then
            return 0
        end

        local fuelConsumer = nil

        if motorizedSpec.consumersByFillTypeName ~= nil then
            fuelConsumer = motorizedSpec.consumersByFillTypeName["DIESEL"]
                or motorizedSpec.consumersByFillTypeName["METHANE"]
                or motorizedSpec.consumersByFillTypeName["ELECTRICCHARGE"]
        end

        if fuelConsumer == nil and motorizedSpec.consumers ~= nil then
            for _, consumer in pairs(motorizedSpec.consumers) do
                if consumer ~= nil and consumer.fillType ~= nil then
                    if consumer.fillType == FillType.DIESEL
                    or consumer.fillType == FillType.METHANE
                    or consumer.fillType == FillType.ELECTRICCHARGE then
                        fuelConsumer = consumer
                        break
                    end
                end
            end
        end

        local baseFuelUsageLh = 0
        if fuelConsumer ~= nil and fuelConsumer.usage ~= nil then
            if fuelConsumer.permanentConsumption then
                baseFuelUsageLh = (fuelConsumer.usage or 0) * 60 * 60 * 1000
            else
                baseFuelUsageLh = fuelConsumer.usage or 0
            end
        end

        local currentFuelUsageLh = RealisticMechanicalSystems.sanitizeNumber(motorizedSpec.lastFuelUsage, 0, 0, 10000)

        local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
        local usageFactor = 1.5
        if missionInfo ~= nil then
            if missionInfo.fuelUsage == 1 then
                usageFactor = 1.0
            elseif missionInfo.fuelUsage == 3 then
                usageFactor = 2.5
            end
        end

        local damageFactor = 1.0
        if vehicle.getVehicleDamage ~= nil and Motorized ~= nil and Motorized.DAMAGED_USAGE_INCREASE ~= nil then
            local vehicleDamage = vehicle:getVehicleDamage() or 0
            if vehicleDamage > 0 then
                damageFactor = damageFactor * (1 + vehicleDamage * Motorized.DAMAGED_USAGE_INCREASE)
            end
        end

        local maxFuelUsageLh = baseFuelUsageLh * usageFactor * damageFactor
        if maxFuelUsageLh > 0 then
            return currentFuelUsageLh / maxFuelUsageLh
        end

        return 0
    end

    fuelState.level = resolveFuelLevel()

    if vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() and not spec.isElectricVehicle then
        fuelState.currentUsageRatio = resolveFuelUsageRatio()

        local environmentTemp = 20
        if g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.weather ~= nil and g_currentMission.environment.weather.forecast ~= nil then
            local weather = g_currentMission.environment.weather.forecast:getCurrentWeather()
            if weather ~= nil and weather.temperature ~= nil then
                environmentTemp = weather.temperature
            end
        end

        fuelState.temperature = math.max(RealisticMechanicalSystems.sanitizeNumber(spec.engineTemperature, environmentTemp, -80, 160) / 3.6, environmentTemp)

        local idleSpeedThreshold = RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_SPEED_THRESHOLD
        local idleLoadThreshold = RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_LOAD_THRESHOLD
        local motorLoad = vehicle.getMotorLoadPercentage ~= nil and (vehicle:getMotorLoadPercentage() or 0) or 0
        local idleTimer = math.max(tonumber(fuelState.idleTimer) or 0, 0)
        local isIdle = (vehicle:getLastSpeed() or 0) <= idleSpeedThreshold and motorLoad <= idleLoadThreshold

        if isIdle then
            idleTimer = math.min(idleTimer + (dt / 1000), RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_FACTOR_MAX_TIMER)
        else
            idleTimer = 0
        end

        fuelState.idleTimer = idleTimer
        fuelState.wetStackingLevel = RMS_Exhaust.calculateWetStackingLevel({
            currentLevel = fuelState.wetStackingLevel,
            idleTimer = idleTimer,
            load = motorLoad,
            dt = dt,
            engineTemperature = spec.rawEngineTemperature or spec.engineTemperature,
            isIdle = isIdle,
            isDiesel = spec.isDieselVehicle,
            isMotorStarted = true
        })
    else
        fuelState.currentUsageRatio = 0
        fuelState.temperature = 0
        fuelState.idleTimer = 0
    end
end

--- update state
function RealisticMechanicalSystems:updateVehicleStateSnapshot(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer or spec == nil or spec.isExcludedVehicle then return end

    local delayOne = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_ONE
    local delayTwo = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_TWO
    local delayThree = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_THREE

    spec.updateVehicleStateTimerOne = spec.updateVehicleStateTimerOne + dt
    spec.updateVehicleStateTimerTwo = spec.updateVehicleStateTimerTwo + dt
    spec.updateVehicleStateTimerThree = spec.updateVehicleStateTimerThree + dt

    --- GROUP 1 ---
    if spec.updateVehicleStateTimerOne >= delayOne then
        spec.updateVehicleStateTimerOne = spec.updateVehicleStateTimerOne % delayOne
        --- avgAbsDiffAcc for dynamic motorLoad calculations
        updateAvgAbsDiffAccWindow(spec, self:getMotor(), delayOne)
        --- dynamic motorLoad
        updateDynamicMotorLoad(self, delayOne)
    end

    --- GROUP 2 ---
    if spec.updateVehicleStateTimerTwo >= delayTwo then
        spec.updateVehicleStateTimerTwo = spec.updateVehicleStateTimerTwo % delayTwo
        --- isCranking
        updateStarterState(self)
        --- wheel slip
        updateWheelSlip(self)
        --- chassis vibration
        updateChassisVibState(self, delayTwo)
        --- low speed steering
        updateChassisSteeringState(self, delayTwo)
        --- braking under mass
        updateChassisBrakingState(self)
    end
    
    --- GROUP 3 ---
    if spec.updateVehicleStateTimerThree >= delayThree then
        spec.updateVehicleStateTimerThree = spec.updateVehicleStateTimerThree % delayThree
        --- max friction force
        updateActiveDraftStats(self)
        --- wheel ground state
        updateWheelGroundState(self)
        --- implement chain state
        updateImplementChainState(self, delayThree)
        --- fuel state
        updateFuelState(self, delayThree)
        --- is vehicle under roof
        spec.isUnderRoof = self:isUnderRoof()
    end
end
