ADS_Drivetrain = ADS_Drivetrain or {}

ADS_Drivetrain.MODE = {
    TWO_WD  = 0,
    FOUR_WD = 1,
    AUTO    = 2
}

ADS_Drivetrain.MODE_L10N = {
    [0] = "ads_drivetrain_mode_4x2",
    [1] = "ads_drivetrain_mode_4wd",
    [2] = "ads_drivetrain_mode_auto"
}

local LOCKED_MIN_TORQUE_RATIO = 0.1
local LOCKED_MAX_TORQUE_RATIO = 0.9
local LOCKED_TORQUE_DEAD_ZONE = 0.02
local LOCKED_WHEEL_SPEED_FILTER = 0.2
local TRACK_STEER_INPUT_EPSILON = 0.001
local DEBUG_SAMPLE_INTERVAL_MS = 400
local DEBUG_RATIO_MIN_SPEED = 0.05
local DEBUG_RATIO_MAX = 99

local sanitizeNumber = AdvancedDamageSystem.sanitizeNumber

local function getConfig()
    return ADS_Config.DRIVETRAIN
end

local evConfigCache = { diff = nil, park = nil, nextReadTime = -math.huge }

local function readEnhancedVehicleSettings()
    local now = g_time or 0
    if evConfigCache.diff ~= nil and now < evConfigCache.nextReadTime then
        return evConfigCache
    end
    evConfigCache.nextReadTime = now + 10000 -- re-read every 10s (menu changes)

    local diffEnabled, parkEnabled = true, true
    local path = getUserProfileAppPath() .. "modSettings/FS25_EnhancedVehicle/FS25_EnhancedVehicle_v1.xml"
    if fileExists(path) then
        local xml = loadXMLFile("adsEvConfig", path)
        if xml ~= nil and xml ~= 0 then
            local diffValue = getXMLBool(xml, "FS25_EnhancedVehicle.global.functions#diffIsEnabled")
            if diffValue ~= nil then diffEnabled = diffValue end
            local parkValue = getXMLBool(xml, "FS25_EnhancedVehicle.global.functions#parkingBrakeIsEnabled")
            if parkValue ~= nil then parkEnabled = parkValue end
            delete(xml)
        end
    end

    evConfigCache.diff = diffEnabled
    evConfigCache.park = parkEnabled
    return evConfigCache
end

local function getIsEnhancedVehicleLoaded(vehicle)
    if rawget(_G, "FS25_EnhancedVehicle") ~= nil then
        return true
    end
    if g_modIsLoaded ~= nil and g_modIsLoaded["FS25_EnhancedVehicle"] == true then
        return true
    end
    return vehicle ~= nil and vehicle.vData ~= nil and vehicle.vData.is ~= nil
end

function ADS_Drivetrain.isExternallyManaged(vehicle)
    local ev = rawget(_G, "FS25_EnhancedVehicle")
    if ev ~= nil and ev.functionDiffIsEnabled ~= nil then
        return ev.functionDiffIsEnabled == true
    end

    if getIsEnhancedVehicleLoaded(vehicle) then
        return readEnhancedVehicleSettings().diff
    end

    return false
end

function ADS_Drivetrain.isParkBrakeExternallyManaged(vehicle)
    local ev = rawget(_G, "FS25_EnhancedVehicle")
    if ev ~= nil and ev.functionParkingBrakeIsEnabled ~= nil then
        return ev.functionParkingBrakeIsEnabled == true
    end

    if getIsEnhancedVehicleLoaded(vehicle) then
        return readEnhancedVehicleSettings().park
    end

    return false
end

local function getStoreCategoryNames(vehicle)
    if vehicle == nil or vehicle.configFileName == nil or g_storeManager == nil then
        return nil
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return nil
    end

    if storeItem.categoryNames ~= nil and #storeItem.categoryNames > 0 then
        return storeItem.categoryNames
    end

    if storeItem.categoryName ~= nil then
        return { storeItem.categoryName }
    end

    return nil
end

function ADS_Drivetrain.getIsRoadVehicleCategory(vehicle)
    local categoryNames = getStoreCategoryNames(vehicle)
    if categoryNames == nil then
        return false
    end

    local excludedCategories = getConfig().EXCLUDED_CATEGORIES
    for _, categoryName in ipairs(categoryNames) do
        local normalizedCategoryName = string.upper(tostring(categoryName or ""))
        if excludedCategories ~= nil and excludedCategories[normalizedCategoryName] == true then
            return true
        end
    end

    return false
end

function ADS_Drivetrain.getIsWheelSteerable(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if physics == nil then return false end
    local rotMin = tonumber(physics.rotMin) or 0
    local rotMax = tonumber(physics.rotMax) or 0
    if math.abs(rotMax - rotMin) > 0.01 then
        return true
    end
    return math.abs(tonumber(physics.rotSpeed) or 0) > 0.001
end

local function getWheelLocalZ(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if physics == nil then return 0 end
    return tonumber(physics.positionZ) or (physics.netInfo ~= nil and tonumber(physics.netInfo.z)) or 0
end

local function getWheelAxleSpeed(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if wheel == nil or wheel.node == nil or physics == nil or not physics.wheelShapeCreated then
        return 0
    end
    return tonumber(getWheelShapeAxleSpeed(wheel.node, physics.wheelShape)) or 0
end

-- ==========================================================
--                 TOPOLOGY ANALYSIS
-- ==========================================================

local function collectWheelIndices(differentials, diffIndex0, wheelIndices, visited)
    local runtimeIndex = (tonumber(diffIndex0) or -1) + 1
    if runtimeIndex < 1 or visited[runtimeIndex] then return end
    local differential = differentials[runtimeIndex]
    if differential == nil then return end
    visited[runtimeIndex] = true

    if differential.diffIndex1IsWheel then
        wheelIndices[#wheelIndices + 1] = tonumber(differential.diffIndex1)
    else
        collectWheelIndices(differentials, differential.diffIndex1, wheelIndices, visited)
    end
    if differential.diffIndex2IsWheel then
        wheelIndices[#wheelIndices + 1] = tonumber(differential.diffIndex2)
    else
        collectWheelIndices(differentials, differential.diffIndex2, wheelIndices, visited)
    end
end

local function getAxleScore(vehicle, wheelIndices)
    local steerableCount, zSum, count = 0, 0, 0
    for _, wheelIndex in ipairs(wheelIndices) do
        local wheel = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(wheelIndex) or nil
        if wheel ~= nil then
            count = count + 1
            zSum = zSum + getWheelLocalZ(wheel)
            if ADS_Drivetrain.getIsWheelSteerable(wheel) then
                steerableCount = steerableCount + 1
            end
        end
    end
    if count == 0 then
        return 0, 0
    end
    return steerableCount / count, zSum / count
end

local function getIsTwinTrack(vehicle)
    local spec_crawlers = vehicle.spec_crawlers
    local crawlers = spec_crawlers ~= nil and spec_crawlers.crawlers or nil
    if crawlers == nil or #crawlers ~= 2 then
        return false
    end

    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    if wheels == nil or #wheels == 0 or WheelsUtil == nil then
        return false
    end

    local crawlerTireType = WheelsUtil.getTireType("crawler")
    if crawlerTireType == nil then
        return false
    end

    for _, wheel in ipairs(wheels) do
        local physics = wheel ~= nil and wheel.physics or nil
        if physics == nil or physics.tireType ~= crawlerTireType then
            return false
        end
    end

    return true
end

function ADS_Drivetrain.buildLayout(vehicle)
    local spec_motorized = vehicle.spec_motorized
    local differentials = spec_motorized ~= nil and spec_motorized.differentials or nil
    if differentials == nil or next(differentials) == nil then
        return nil
    end

    local isTwinTrack = getIsTwinTrack(vehicle)
    local layout = {
        differentialCount = #differentials,
        isTwinTrack = isTwinTrack,
        originals = {},
        centerIdx0 = nil,
        primaryIdx0 = nil,
        engageableWheelIndices = {},
        primaryWheelIndices = {},
        lockableIdx0 = {},
        engageableAxleIdx0Set = {}
    }

    local referencedAsChild = {}
    for _, differential in ipairs(differentials) do
        if not differential.diffIndex1IsWheel then
            referencedAsChild[(tonumber(differential.diffIndex1) or -1) + 1] = true
        end
        if not differential.diffIndex2IsWheel then
            referencedAsChild[(tonumber(differential.diffIndex2) or -1) + 1] = true
        end
    end

    for i, differential in ipairs(differentials) do
        local idx0 = i - 1
        layout.originals[idx0] = {
            torqueRatio = tonumber(differential.torqueRatio) or 0.5,
            maxSpeedRatio = tonumber(differential.maxSpeedRatio) or 1.3,
            diffIndex1 = differential.diffIndex1,
            diffIndex1IsWheel = differential.diffIndex1IsWheel == true,
            diffIndex2 = differential.diffIndex2,
            diffIndex2IsWheel = differential.diffIndex2IsWheel == true
        }

        local isInterAxle = not differential.diffIndex1IsWheel and not differential.diffIndex2IsWheel
        if isInterAxle and not referencedAsChild[i] and layout.centerIdx0 == nil then
            layout.centerIdx0 = idx0
        end
    end

    if isTwinTrack then
        layout.centerIdx0 = nil
    end

    if layout.centerIdx0 ~= nil then
        local center = differentials[layout.centerIdx0 + 1]
        local out1Idx0 = tonumber(center.diffIndex1) or 0
        local out2Idx0 = tonumber(center.diffIndex2) or 0

        local out1Wheels, out2Wheels = {}, {}
        collectWheelIndices(differentials, out1Idx0, out1Wheels, {})
        collectWheelIndices(differentials, out2Idx0, out2Wheels, {})

        local steer1, z1 = getAxleScore(vehicle, out1Wheels)
        local steer2, z2 = getAxleScore(vehicle, out2Wheels)

        local out1IsEngageable
        if steer1 ~= steer2 then
            out1IsEngageable = steer1 > steer2
        else
            out1IsEngageable = z1 > z2 -- vehicles face +Z
        end

        if out1IsEngageable then
            layout.primaryIdx0 = out2Idx0
            layout.engageableWheelIndices, layout.primaryWheelIndices = out1Wheels, out2Wheels
        else
            layout.primaryIdx0 = out1Idx0
            layout.engageableWheelIndices, layout.primaryWheelIndices = out2Wheels, out1Wheels
        end

        local engageableWheelSet = {}
        for _, wheelIndex in ipairs(layout.engageableWheelIndices) do
            engageableWheelSet[wheelIndex] = true
        end
        for i, differential in ipairs(differentials) do
            if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then
                local idx0 = i - 1
                layout.lockableIdx0[#layout.lockableIdx0 + 1] = idx0
                if engageableWheelSet[tonumber(differential.diffIndex1)] or engageableWheelSet[tonumber(differential.diffIndex2)] then
                    layout.engageableAxleIdx0Set[idx0] = true
                end
            end
        end
    else
        for i, differential in ipairs(differentials) do
            if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then
                local idx0 = i - 1
                layout.primaryIdx0 = layout.primaryIdx0 or idx0
                layout.lockableIdx0[#layout.lockableIdx0 + 1] = idx0
                collectWheelIndices(differentials, idx0, layout.primaryWheelIndices, {})
            end
        end
        if #layout.lockableIdx0 == 0 then
            return nil
        end
    end

    return layout
end

-- ==========================================================
--                SPEC INIT / STATE ACCESS
-- ==========================================================

function ADS_Drivetrain.initSpec(vehicle)
    local spec = vehicle.spec_AdvancedDamageSystem
    spec.drivetrain = {
        layout = nil,
        layoutAnalyzed = false,
        hasControl = false,
        hasCenterDiff = false,
        externallyManaged = false,
        parkExternallyManaged = false,
        driveMode = ADS_Drivetrain.MODE.TWO_WD,
        autoEngaged = false,
        diffLockRequested = false,
        diffLockEngaged = false,
        parkBrake = false,
        windupStress = 0,
        windupWearFactor = 0,
        windupActive = false,
        _windupDamageLatched = false,
        _appliedMode = nil,
        _appliedLock = nil,
        _activeDifferentialIndices = nil,
        _activeFourWheelDrive = nil,
        _graphManaged = false,
        _wheelPeripheralSpeeds = {},
        _wasAddedToPhysics = false,
        _autoConditionTimer = 0,
        _lastNotifiedMode = nil,
        _lastNotifiedLock = nil,
        _lastNotifiedPark = nil,
        _windupWarningCooldown = 0,
        _parkWarningCooldown = 0,
        _wasLocallyControlled = false,
        _parkNotifyGraceMs = 0
    }
end

function ADS_Drivetrain.getState(vehicle)
    local spec = vehicle.spec_AdvancedDamageSystem
    return spec ~= nil and spec.drivetrain or nil
end

function ADS_Drivetrain.getIsAvailable(vehicle)
    local state = ADS_Drivetrain.getState(vehicle)
    return state ~= nil
        and state.hasControl == true
        and not state.externallyManaged
        and getConfig().ENABLED
end

function ADS_Drivetrain.getHasCenterDifferential(vehicle)
    local state = ADS_Drivetrain.getState(vehicle)
    return state ~= nil and state.hasCenterDiff == true
end

local function ensureLayout(vehicle, state)
    if state.layoutAnalyzed then
        return state.layout ~= nil
    end
    local spec_wheels = vehicle.spec_wheels
    if spec_wheels == nil or spec_wheels.wheels == nil or #spec_wheels.wheels == 0 then
        return false
    end
    state.layoutAnalyzed = true

    if ADS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        state.layout = nil
        state.hasControl = false
        state.hasCenterDiff = false
        AdvancedDamageSystem.raiseADSDirty(vehicle, AdvancedDamageSystem.SYNC_GROUP.DRIVETRAIN)
        return false
    end

    state.layout = ADS_Drivetrain.buildLayout(vehicle)
    state.hasControl = state.layout ~= nil
    state.hasCenterDiff = state.layout ~= nil and state.layout.centerIdx0 ~= nil
    AdvancedDamageSystem.raiseADSDirty(vehicle, AdvancedDamageSystem.SYNC_GROUP.DRIVETRAIN)
    return state.layout ~= nil
end

-- ==========================================================
--              PHYSICS APPLICATION (SERVER)
-- ==========================================================

local function getEffectiveFourWheelDrive(state)
    if state.layout == nil or state.layout.centerIdx0 == nil then
        return true -- single-axle machines are always "engaged"
    end
    if state.driveMode == ADS_Drivetrain.MODE.FOUR_WD then
        return true
    elseif state.driveMode == ADS_Drivetrain.MODE.AUTO then
        return state.autoEngaged
    end
    return false
end

local function getIsNativeLock(layout, fourWheelDrive)
    return fourWheelDrive and layout.centerIdx0 ~= nil
end

local function getTargetSpeedRatio(original, lockEngaged, nativeLock)
    local C = getConfig()

    if original.diffIndex1IsWheel and original.diffIndex2IsWheel then
        if lockEngaged then
            return nativeLock and original.maxSpeedRatio or C.LOCKED_AXLE_SPEED_RATIO
        end
        return math.max(original.maxSpeedRatio, C.OPEN_AXLE_SPEED_RATIO)
    end

    return original.maxSpeedRatio
end

local function buildDifferentialPlan(vehicle, state, useFullGraph)
    local layout = state.layout
    local lockEngaged = state.diffLockEngaged == true
    local nativeLock = getIsNativeLock(layout, useFullGraph)
    local plan = {}
    local sourceToNative = {}
    local visiting = {}

    local function addSourceDifferential(sourceIdx0)
        local nativeIdx0 = sourceToNative[sourceIdx0]
        if nativeIdx0 ~= nil then
            return nativeIdx0
        end
        if visiting[sourceIdx0] then
            return nil
        end

        local original = layout.originals[sourceIdx0]
        if original == nil then
            return nil
        end
        visiting[sourceIdx0] = true

        local function resolveOutput(outputIndex, outputIsWheel)
            if outputIsWheel then
                local wheel = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(outputIndex) or nil
                local physics = wheel ~= nil and wheel.physics or nil
                local wheelShape = tonumber(physics ~= nil and physics.wheelShape) or 0
                if wheelShape == 0 then
                    return nil
                end
                return wheelShape
            end
            return addSourceDifferential(outputIndex)
        end

        local output1 = resolveOutput(original.diffIndex1, original.diffIndex1IsWheel)
        local output2 = resolveOutput(original.diffIndex2, original.diffIndex2IsWheel)
        if output1 == nil or output2 == nil then
            return nil
        end

        nativeIdx0 = #plan
        plan[#plan + 1] = {
            output1 = output1,
            output1IsWheel = original.diffIndex1IsWheel,
            output2 = output2,
            output2IsWheel = original.diffIndex2IsWheel,
            torqueRatio = original.torqueRatio,
            maxSpeedRatio = getTargetSpeedRatio(original, lockEngaged, nativeLock)
        }
        sourceToNative[sourceIdx0] = nativeIdx0
        visiting[sourceIdx0] = nil
        return nativeIdx0
    end

    if useFullGraph or layout.centerIdx0 == nil then
        for sourceIdx0 = 0, layout.differentialCount - 1 do
            if addSourceDifferential(sourceIdx0) == nil then
                return nil, nil
            end
        end
    elseif layout.primaryIdx0 == nil or addSourceDifferential(layout.primaryIdx0) == nil then
        return nil, nil
    end

    return plan, sourceToNative
end

local function installDifferentialGraph(vehicle, state, useFullGraph)
    local spec_motorized = vehicle.spec_motorized
    if spec_motorized == nil or spec_motorized.motorizedNode == nil or not vehicle.isAddedToPhysics then
        return false
    end

    local plan, sourceToNative = buildDifferentialPlan(vehicle, state, useFullGraph)
    if plan == nil then
        return false
    end

    local node = spec_motorized.motorizedNode
    removeAllDifferentials(node)
    for _, differential in ipairs(plan) do
        addDifferential(
            node,
            differential.output1,
            differential.output1IsWheel,
            differential.output2,
            differential.output2IsWheel,
            differential.torqueRatio,
            differential.maxSpeedRatio
        )
    end
    vehicle:updateMotorProperties()

    state._activeDifferentialIndices = sourceToNative
    state._activeFourWheelDrive = useFullGraph or state.layout.centerIdx0 == nil
    state._graphManaged = true
    return true
end

local function restoreOriginalDifferentialGraph(vehicle, state)
    if not state._graphManaged then
        return true
    end

    if vehicle.isAddedToPhysics and not installDifferentialGraph(vehicle, state, true) then
        return false
    end

    state._activeDifferentialIndices = nil
    state._activeFourWheelDrive = nil
    state._graphManaged = false
    return true
end

function ADS_Drivetrain.applyState(vehicle, force)
    if not vehicle.isServer then return end

    local state = ADS_Drivetrain.getState(vehicle)
    local spec_motorized = vehicle.spec_motorized
    if state == nil or state.layout == nil or spec_motorized == nil or spec_motorized.motorizedNode == nil then
        return
    end
    if not vehicle.isAddedToPhysics then
        return
    end

    local layout = state.layout
    local fourWheelDrive = getEffectiveFourWheelDrive(state)
    if not force
        and state._graphManaged
        and state._activeFourWheelDrive == fourWheelDrive
        and state._appliedMode == fourWheelDrive then
        return
    end

    if not installDifferentialGraph(vehicle, state, fourWheelDrive) then
        return
    end

    state._appliedMode = fourWheelDrive
    state._appliedLock = nil
end

local function getLockedTorqueRatio(original, speed1, speed2, gearRatio)
    local torqueRatio = original.torqueRatio

    if gearRatio < 0 then
        speed1 = -speed1
        speed2 = -speed2
    end

    local isStandstill = speed1 < 0.1389 and speed2 < 0.1389
    local isOutOfRange = not (-0.2778 < speed1 and speed1 < 90 and -0.2778 < speed2 and speed2 < 90)
    if isStandstill or isOutOfRange then
        return torqueRatio
    end

    if speed1 < speed2 then
        torqueRatio = 1 - (math.max(speed1, 0) / speed2) * (1 - torqueRatio)
    elseif speed2 < speed1 then
        torqueRatio = torqueRatio * (math.max(speed2, 0) / speed1)
    end

    if math.abs(torqueRatio - original.torqueRatio) < LOCKED_TORQUE_DEAD_ZONE then
        return original.torqueRatio
    end

    return math.clamp(torqueRatio, LOCKED_MIN_TORQUE_RATIO, LOCKED_MAX_TORQUE_RATIO)
end

local function getDifferentialOutputSpeeds(vehicle, state, differentialIdx0, wheelSpeeds, depth)
    local layout = state.layout
    if depth > layout.differentialCount then
        return 0, 0
    end

    local differential = layout.originals[differentialIdx0]
    if differential == nil then
        return 0, 0
    end

    local function getOutputSpeed(outputIndex, outputIsWheel)
        if outputIsWheel then
            local speed = wheelSpeeds[outputIndex]
            if speed ~= nil then
                return speed
            end

            local wheel = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(outputIndex) or nil
            local physics = wheel ~= nil and wheel.physics or nil
            local rawSpeed = 0
            if wheel ~= nil and wheel.node ~= nil and physics ~= nil and physics.wheelShapeCreated then
                rawSpeed = getWheelAxleSpeed(wheel) * (tonumber(physics.radius) or 0)
            end

            local previousSpeed = state._wheelPeripheralSpeeds[outputIndex]
            speed = previousSpeed == nil and rawSpeed
                or previousSpeed + LOCKED_WHEEL_SPEED_FILTER * (rawSpeed - previousSpeed)
            state._wheelPeripheralSpeeds[outputIndex] = speed
            wheelSpeeds[outputIndex] = speed
            return speed
        end

        local childSpeed1, childSpeed2 = getDifferentialOutputSpeeds(vehicle, state, outputIndex, wheelSpeeds, depth + 1)
        return (childSpeed1 + childSpeed2) * 0.5
    end

    return getOutputSpeed(differential.diffIndex1, differential.diffIndex1IsWheel),
        getOutputSpeed(differential.diffIndex2, differential.diffIndex2IsWheel)
end

local function applyDifferentialLock(vehicle, state)
    local spec_motorized = vehicle.spec_motorized
    local activeIndices = state._activeDifferentialIndices
    if spec_motorized == nil or spec_motorized.motorizedNode == nil or activeIndices == nil or not vehicle.isAddedToPhysics then
        return
    end

    local lockEngaged = state.diffLockEngaged == true
    if not lockEngaged and state._appliedLock == false then
        return
    end

    local layout = state.layout
    local nativeLock = getIsNativeLock(layout, state._activeFourWheelDrive == true)
    local wheelSpeeds = {}
    local gearRatio = tonumber(spec_motorized.motor ~= nil and spec_motorized.motor.gearRatio) or 0

    if lockEngaged and state._appliedLock ~= true then
        state._wheelPeripheralSpeeds = {}
    else
        state._wheelPeripheralSpeeds = state._wheelPeripheralSpeeds or {}
    end

    for sourceIdx0 = 0, layout.differentialCount - 1 do
        local nativeIdx0 = activeIndices[sourceIdx0]
        local original = layout.originals[sourceIdx0]
        if nativeIdx0 ~= nil and original ~= nil then
            local isAxleDifferential = original.diffIndex1IsWheel and original.diffIndex2IsWheel
            local torqueRatio = original.torqueRatio
            local maxSpeedRatio = getTargetSpeedRatio(original, lockEngaged, nativeLock)
            if lockEngaged and isAxleDifferential and not nativeLock then
                local speed1, speed2 = getDifferentialOutputSpeeds(vehicle, state, sourceIdx0, wheelSpeeds, 1)
                torqueRatio = getLockedTorqueRatio(original, speed1, speed2, gearRatio)
            end

            updateDifferential(spec_motorized.motorizedNode, nativeIdx0, torqueRatio, maxSpeedRatio)
        end
    end

    state._appliedLock = lockEngaged
end

-- ==========================================================
--                 COMMAND SETTERS (MP-SAFE)
-- ==========================================================

function ADS_Drivetrain.setDrivetrainState(vehicle, driveMode, diffLockRequested, parkBrake, noEventSend)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then return end

    driveMode = math.clamp(math.floor(tonumber(driveMode) or state.driveMode), 0, 2)
    if not getConfig().ALLOW_AUTO_MODE and driveMode == ADS_Drivetrain.MODE.AUTO then
        driveMode = ADS_Drivetrain.MODE.FOUR_WD
    end
    diffLockRequested = diffLockRequested == true
    if parkBrake == nil then parkBrake = state.parkBrake end
    parkBrake = parkBrake == true

    local changed = state.driveMode ~= driveMode
        or state.diffLockRequested ~= diffLockRequested
        or state.parkBrake ~= parkBrake
    state.driveMode = driveMode
    state.diffLockRequested = diffLockRequested
    state.parkBrake = parkBrake

    if vehicle.isServer then
        if state.driveMode ~= ADS_Drivetrain.MODE.AUTO then
            state.autoEngaged = false
            state._autoConditionTimer = 0
        end
        if changed then
            AdvancedDamageSystem.raiseADSDirty(vehicle, AdvancedDamageSystem.SYNC_GROUP.DRIVETRAIN)
        end
    elseif changed then
        ADS_DrivetrainEvent.sendEvent(vehicle, noEventSend)
    end
end

function ADS_Drivetrain.setParkBrake(vehicle, engaged, noEventSend)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then return end
    ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, engaged, noEventSend)
end

function ADS_Drivetrain.cycleDriveMode(vehicle)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil or not state.hasCenterDiff then return end

    local nextMode
    if state.driveMode == ADS_Drivetrain.MODE.TWO_WD then
        nextMode = ADS_Drivetrain.MODE.FOUR_WD
    elseif state.driveMode == ADS_Drivetrain.MODE.FOUR_WD then
        nextMode = getConfig().ALLOW_AUTO_MODE and ADS_Drivetrain.MODE.AUTO or ADS_Drivetrain.MODE.TWO_WD
    else
        nextMode = ADS_Drivetrain.MODE.TWO_WD
    end

    ADS_Drivetrain.setDrivetrainState(vehicle, nextMode, state.diffLockRequested, state.parkBrake)
end

function ADS_Drivetrain.toggleDiffLock(vehicle)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil or not state.hasControl then return end
    ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, not state.diffLockRequested, state.parkBrake)
end

function ADS_Drivetrain.toggleParkBrake(vehicle)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then return end
    ADS_Drivetrain.setParkBrake(vehicle, not state.parkBrake)
end

-- ==========================================================
--                  SIMULATION UPDATE
-- ==========================================================

local function updateAutoMode(vehicle, state, spec, dt)
    if state.driveMode ~= ADS_Drivetrain.MODE.AUTO then return end

    local C = getConfig()
    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
    local slip = sanitizeNumber(spec.wheelSlipIntensity, 0, 0, 3)
    local motorLoad = sanitizeNumber(spec.dynamicMotorLoad or 0, 0, 0, 1.5)

    local wantsEngage = slip > C.AUTO_ENGAGE_SLIP_THRESHOLD
        or (speed < C.AUTO_ENGAGE_SPEED and motorLoad > C.AUTO_ENGAGE_LOAD_THRESHOLD)

    if state.autoEngaged then
        local wantsRelease = speed > C.AUTO_DISENGAGE_SPEED and slip < 0.05
        if wantsRelease then
            state._autoConditionTimer = state._autoConditionTimer + dt
            if state._autoConditionTimer >= C.AUTO_HYSTERESIS_MS then
                state.autoEngaged = false
                state._autoConditionTimer = 0
            end
        else
            state._autoConditionTimer = 0
        end
    else
        if wantsEngage then
            state.autoEngaged = true
            state._autoConditionTimer = 0
        end
    end
end

local function updateDiffLockState(vehicle, state, dt)
    local C = getConfig()
    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)

    if state.diffLockRequested and vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, false, state.parkBrake, false)
        return
    end

    if state.diffLockRequested then
        if state.diffLockEngaged then
            if speed > C.DIFFLOCK_AUTO_RELEASE_SPEED then
                state.diffLockEngaged = false
                ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, false, state.parkBrake, false)
            end
        else
            if speed <= C.DIFFLOCK_AUTO_RELEASE_SPEED then
                state.diffLockEngaged = true
            end
        end
    else
        state.diffLockEngaged = false
    end
end

function ADS_Drivetrain.getIsTurning(vehicle)
    local spec = vehicle.spec_AdvancedDamageSystem
    local steerState = spec ~= nil and spec.chassisSteerState or nil
    local steeringAngle = tonumber(steerState ~= nil and steerState.angleMagnitude or 0) or 0
    if steeringAngle > getConfig().WINDUP_STEER_THRESHOLD then
        return true
    end

    return getIsTwinTrack(vehicle)
        and (tonumber(steerState ~= nil and steerState.inputMagnitude or 0) or 0) > TRACK_STEER_INPUT_EPSILON
end

local function updateWindupModel(vehicle, state, spec, dt)
    local C = getConfig()
    local fourWheelDrive = state.layout ~= nil and state.layout.centerIdx0 ~= nil and getEffectiveFourWheelDrive(state)
    local windupFactor = 0

    if state.diffLockEngaged then
        windupFactor = 1.0
    elseif fourWheelDrive then
        windupFactor = math.max(tonumber(C.WINDUP_4WD_FACTOR) or 0, 0)
    end

    if not state.diffLockEngaged then
        state._windupDamageLatched = false
    end

    if not C.WINDUP_DAMAGE_ENABLED
        or windupFactor <= 0
        or (vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive()) then
        state.windupActive = false
        state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE, 0)
        state.windupWearFactor = 0
        return
    end

    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
    local friction = sanitizeNumber(spec.avgTireGroundFrictionCoeff, 0, 0, 3)
    local steerState = spec.chassisSteerState
    local steering = sanitizeNumber(steerState ~= nil and steerState.angleMagnitude or 0, 0, 0)
    local trackSteeringInput = sanitizeNumber(steerState ~= nil and steerState.inputMagnitude or 0, 0, 0, 1)
    local isTwinTrack = state.layout ~= nil and state.layout.isTwinTrack == true
    local isSteering = (isTwinTrack and trackSteeringInput > TRACK_STEER_INPUT_EPSILON)
        or steering > C.WINDUP_STEER_THRESHOLD
    local surfaceFactor = state.diffLockEngaged and 1 or sanitizeNumber(spec.avgGroundSurfaceFactor, 0, 0, 1)

    local isWindingUp = speed > 1.0
        and isSteering
        and surfaceFactor > 0
        and friction >= C.WINDUP_FRICTION_THRESHOLD

    state.windupActive = isWindingUp

    if isWindingUp then
        local stressLimit = state.diffLockEngaged and 1.0 or math.max(tonumber(C.WINDUP_4WD_MAX_STRESS) or 0, 0)
        local steerFactor = isTwinTrack and trackSteeringInput or math.min(steering / 0.5, 1.0)
        local frictionFactor = math.min(friction / math.max(C.WINDUP_FRICTION_THRESHOLD, 0.001), 1.5)
        local speedFactor = math.min(speed / 10.0, 1.0)
        local rate = C.WINDUP_ACCUMULATION_RATE * steerFactor * frictionFactor * speedFactor * surfaceFactor * windupFactor
        if state.windupStress > stressLimit then
            state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE, stressLimit)
        else
            state.windupStress = math.min(state.windupStress + (dt / 1000) * rate, stressLimit)
        end
    else
        local releaseBoost = 1.0 + (1.0 - surfaceFactor) + math.max(1.2 - friction, 0)
        state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE * releaseBoost, 0)
    end

    if state.windupStress <= 0 then
        state._windupDamageLatched = false
    end

    if state.diffLockEngaged and state.windupStress >= 1.0 and not state._windupDamageLatched then
        local transmissionSystem = spec.systems ~= nil and spec.systems.transmission or nil
        if transmissionSystem ~= nil and transmissionSystem.enabled == true and vehicle.applyInstantDamageToSystem ~= nil then
            vehicle:applyInstantDamageToSystem(AdvancedDamageSystem.SYSTEMS.TRANSMISSION, C.WINDUP_INSTANT_DAMAGE)
            state._windupDamageLatched = true
            state.windupStress = 0.5
            AdvancedDamageSystem.raiseADSDirty(vehicle, AdvancedDamageSystem.SYNC_GROUP.WEAR)
        end
    end

    if state.windupStress > 0 and isWindingUp then
        state.windupWearFactor = state.windupStress * C.WINDUP_WEAR_MULTIPLIER * windupFactor
    else
        state.windupWearFactor = 0
    end

end

local function notifyParkBrakeChange(state)
    if state._lastNotifiedPark ~= state.parkBrake then
        if state._lastNotifiedPark ~= nil then
            local key = state.parkBrake and "ads_drivetrain_notify_park_on" or "ads_drivetrain_notify_park_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
            ADS_SoundManager.playSample(ADS_Main.samples.notification2D)
        end
        state._lastNotifiedPark = state.parkBrake
    end
end

local function updateLocalNotifications(vehicle, state, dt)
    if g_dedicatedServerInfo ~= nil then return end
    local isControlled = g_currentMission ~= nil
        and vehicle:getIsActiveForInput(true)
        and not vehicle:getIsAIActive()
    if not isControlled then
        state._lastNotifiedMode = state.driveMode
        state._lastNotifiedAutoEngaged = state.autoEngaged
        state._lastNotifiedLock = state.diffLockEngaged

        if state._wasLocallyControlled then
            state._parkNotifyGraceMs = 1500
        end
        if (state._parkNotifyGraceMs or 0) > 0 then
            state._parkNotifyGraceMs = math.max(state._parkNotifyGraceMs - dt, 0)
            notifyParkBrakeChange(state)
        else
            state._lastNotifiedPark = state.parkBrake
        end
        state._wasLocallyControlled = false
        return
    end
    state._wasLocallyControlled = true

    local driveModeChanged = state._lastNotifiedMode ~= state.driveMode
    if driveModeChanged then
        if state._lastNotifiedMode ~= nil then
            local modeText = g_i18n:getText(ADS_Drivetrain.MODE_L10N[state.driveMode] or "ads_drivetrain_mode_4wd")
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, string.format(g_i18n:getText("ads_drivetrain_notify_mode"), modeText))
            ADS_SoundManager.playSample(ADS_Main.samples.notification2D)
        end
        state._lastNotifiedMode = state.driveMode
    end

    if driveModeChanged or state.driveMode ~= ADS_Drivetrain.MODE.AUTO then
        state._lastNotifiedAutoEngaged = state.autoEngaged
    elseif state._lastNotifiedAutoEngaged ~= state.autoEngaged then
        if state._lastNotifiedAutoEngaged ~= nil then
            local modeKey = state.autoEngaged and "ads_drivetrain_mode_4wd" or "ads_drivetrain_mode_4x2"
            local modeText = g_i18n:getText(modeKey)
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, string.format(g_i18n:getText("ads_drivetrain_notify_mode"), modeText))
            ADS_SoundManager.playSample(ADS_Main.samples.notification2D)
        end
        state._lastNotifiedAutoEngaged = state.autoEngaged
    end

    if state._lastNotifiedLock ~= state.diffLockEngaged then
        if state._lastNotifiedLock ~= nil then
            local key = state.diffLockEngaged and "ads_drivetrain_notify_lock_on" or "ads_drivetrain_notify_lock_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
            ADS_SoundManager.playSample(ADS_Main.samples.notification2D)
        end
        state._lastNotifiedLock = state.diffLockEngaged
    end

    notifyParkBrakeChange(state)

    state._parkWarningCooldown = math.max((state._parkWarningCooldown or 0) - dt, 0)
    if state.parkBrake and not getConfig().PARKBRAKE_AUTO_MODE and vehicle.spec_drivable ~= nil then
        local axisForward = math.abs(tonumber(vehicle.spec_drivable.axisForward) or 0)
        if axisForward > 0.2 and state._parkWarningCooldown <= 0 then
            g_currentMission:showBlinkingWarning(g_i18n:getText("ads_drivetrain_warning_parkbrake"), 2000)
            state._parkWarningCooldown = 4000
        end
    end

    state._windupWarningCooldown = math.max((state._windupWarningCooldown or 0) - dt, 0)
    local C = getConfig()
    local warningThreshold = state.diffLockEngaged and C.WINDUP_WARNING_THRESHOLD or C.WINDUP_4WD_WARNING_THRESHOLD
    if state.windupActive and state.windupStress > warningThreshold and state._windupWarningCooldown <= 0 then
        local warningKey = state.diffLockEngaged and "ads_drivetrain_warning_difflock_windup" or "ads_drivetrain_warning_4wd_windup"
        g_currentMission:showBlinkingWarning(g_i18n:getText(warningKey), 2500)
        state._windupWarningCooldown = 5000
    end
end

local function updateParkBrakeState(vehicle, state, dt)
    if not getConfig().PARKBRAKE_ENABLED or state.parkExternallyManaged then
        if state.parkBrake then
            ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        end
        return
    end

    if state.parkBrake and vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        return
    end

    if getConfig().PARKBRAKE_AUTO_MODE and not state.parkBrake then
        local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
        if not vehicle:getIsControlled() and not vehicle:getIsAIActive() and speed < 1.0 then
            ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, true, false)
        end
    end

    if getConfig().PARKBRAKE_AUTO_MODE and state.parkBrake and vehicle:getIsControlled() then
        local axisForward = vehicle.spec_drivable ~= nil and math.abs(tonumber(vehicle.spec_drivable.axisForward) or 0) or 0
        if axisForward > 0.2 then
            ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        end
    end
end

--- Instantaneous wheel speed ratio per axle differential, with the speed ratio ADS currently enforces.
local function updateDebugAxleRatios(vehicle, state, dbg)
    local layout = state.layout
    local activeIndices = state._activeDifferentialIndices
    local entries = dbg.axleRatios or {}
    dbg.axleRatios = entries

    if layout == nil or activeIndices == nil then
        for index = #entries, 1, -1 do
            entries[index] = nil
        end
        return
    end

    local lockEngaged = state.diffLockEngaged == true
    local nativeLock = getIsNativeLock(layout, state._activeFourWheelDrive == true)
    local entryCount = 0

    for sourceIdx0 = 0, layout.differentialCount - 1 do
        local original = layout.originals[sourceIdx0]
        if original ~= nil and original.diffIndex1IsWheel and original.diffIndex2IsWheel
                and activeIndices[sourceIdx0] ~= nil then
            entryCount = entryCount + 1
            local entry = entries[entryCount] or {}
            entries[entryCount] = entry

            entry.label = string.format("W%d/W%d", original.diffIndex1, original.diffIndex2)
            entry.cap = getTargetSpeedRatio(original, lockEngaged, nativeLock)

            local wheel1 = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(original.diffIndex1) or nil
            local wheel2 = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(original.diffIndex2) or nil
            local speed1 = math.abs(getWheelAxleSpeed(wheel1))
            local speed2 = math.abs(getWheelAxleSpeed(wheel2))
            local fast, slow = math.max(speed1, speed2), math.min(speed1, speed2)

            entry.ratio = nil
            if fast >= DEBUG_RATIO_MIN_SPEED then
                entry.ratio = math.min(fast / math.max(slow, fast / DEBUG_RATIO_MAX), DEBUG_RATIO_MAX)
            end
        end
    end

    for index = #entries, entryCount + 1, -1 do
        entries[index] = nil
    end
end

local function updateDebugData(vehicle, state, spec)
    if not ADS_Config.DEBUG or spec.debugData == nil or spec.debugData.drivetrain == nil then
        return
    end

    local dbg = spec.debugData.drivetrain
    dbg.hasControl = state.hasControl
    dbg.hasCenterDiff = state.hasCenterDiff
    dbg.externallyManaged = state.externallyManaged
    dbg.driveMode = state.driveMode
    dbg.autoEngaged = state.autoEngaged
    dbg.diffLockEngaged = state.diffLockEngaged
    dbg.parkBrake = state.parkBrake
    dbg.windupStress = state.windupStress
    dbg.windupWearFactor = state.windupWearFactor

    local now = g_time or 0
    updateDebugAxleRatios(vehicle, state, dbg)

    if now - (dbg.wheelSampleTime or -math.huge) < DEBUG_SAMPLE_INTERVAL_MS then
        return
    end
    dbg.wheelSampleTime = now

    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    local wheelAxleSpeeds = dbg.wheelAxleSpeeds or {}
    local wheelCount = wheels ~= nil and #wheels or 0
    for wheelIndex = 1, wheelCount do
        wheelAxleSpeeds[wheelIndex] = getWheelAxleSpeed(wheels[wheelIndex])
    end
    for wheelIndex = #wheelAxleSpeeds, wheelCount + 1, -1 do
        wheelAxleSpeeds[wheelIndex] = nil
    end
    dbg.wheelAxleSpeeds = wheelAxleSpeeds
end

function ADS_Drivetrain.updateDrivetrain(vehicle, dt)
    local spec = vehicle.spec_AdvancedDamageSystem
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    if not vehicle.isServer then
        updateLocalNotifications(vehicle, state, dt)
        return
    end

    if not ensureLayout(vehicle, state) then return end

    local externallyManaged = ADS_Drivetrain.isExternallyManaged(vehicle)
    local parkExternallyManaged = ADS_Drivetrain.isParkBrakeExternallyManaged(vehicle)
    local managementChanged = state.externallyManaged ~= externallyManaged
        or state.parkExternallyManaged ~= parkExternallyManaged
    if managementChanged then
        state.externallyManaged = externallyManaged
        state.parkExternallyManaged = parkExternallyManaged
        AdvancedDamageSystem.raiseADSDirty(vehicle, AdvancedDamageSystem.SYNC_GROUP.DRIVETRAIN)
    end

    if not getConfig().ENABLED or externallyManaged then
        if state._graphManaged or state._appliedMode ~= nil or state._appliedLock ~= nil then
            state.autoEngaged = false
            state.diffLockEngaged = false
            if restoreOriginalDifferentialGraph(vehicle, state) then
                state._appliedMode = nil
                state._appliedLock = nil
            end
        end

        local hadWindupState = state.windupActive or state.windupStress ~= 0 or state.windupWearFactor ~= 0
        state._windupDamageLatched = false
        state.windupActive = false
        if hadWindupState then
            state.windupStress = 0
            state.windupWearFactor = 0
            AdvancedDamageSystem.raiseADSDirty(vehicle, AdvancedDamageSystem.SYNC_GROUP.DRIVETRAIN)
        end
        return
    end

    if state.driveMode == ADS_Drivetrain.MODE.AUTO and not getConfig().ALLOW_AUTO_MODE then
        ADS_Drivetrain.setDrivetrainState(vehicle, ADS_Drivetrain.MODE.FOUR_WD, state.diffLockRequested, state.parkBrake, false)
    end

    local isAddedToPhysics = vehicle.isAddedToPhysics == true
    local physicsRestored = isAddedToPhysics and not state._wasAddedToPhysics
    state._wasAddedToPhysics = isAddedToPhysics

    local prevAutoEngaged = state.autoEngaged
    local prevDiffLockEngaged = state.diffLockEngaged
    local prevWindupActive = state.windupActive
    local prevWindupQuantized = math.floor(sanitizeNumber(state.windupStress, 0, 0, 1) * 255 + 0.5)

    updateAutoMode(vehicle, state, spec, dt)
    updateDiffLockState(vehicle, state, dt)
    updateParkBrakeState(vehicle, state, dt)
    updateWindupModel(vehicle, state, spec, dt)
    ADS_Drivetrain.applyState(vehicle, physicsRestored)
    applyDifferentialLock(vehicle, state)

    local windupQuantized = math.floor(sanitizeNumber(state.windupStress, 0, 0, 1) * 255 + 0.5)
    local physicalStateChanged = prevAutoEngaged ~= state.autoEngaged
        or prevDiffLockEngaged ~= state.diffLockEngaged
        or prevWindupActive ~= state.windupActive
        or prevWindupQuantized ~= windupQuantized
    if physicalStateChanged then
        AdvancedDamageSystem.raiseADSDirty(vehicle, AdvancedDamageSystem.SYNC_GROUP.DRIVETRAIN)
    end

    updateLocalNotifications(vehicle, state, dt)
    updateDebugData(vehicle, state, spec)
end

function ADS_Drivetrain.getWindupWearFactor(vehicle)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then return 0 end
    return sanitizeNumber(state.windupWearFactor, 0, 0, 100)
end

-- ==========================================================
--                MP STREAMS / SAVEGAME
-- ==========================================================

function ADS_Drivetrain.writeStreamState(vehicle, streamId)
    local state = ADS_Drivetrain.getState(vehicle)
    streamWriteBool(streamId, state ~= nil and state.hasControl or false)
    streamWriteBool(streamId, state ~= nil and state.hasCenterDiff or false)
    streamWriteBool(streamId, state ~= nil and state.externallyManaged or false)
    streamWriteBool(streamId, state ~= nil and state.parkExternallyManaged or false)
    streamWriteUIntN(streamId, state ~= nil and state.driveMode or ADS_Drivetrain.MODE.FOUR_WD, 2)
    streamWriteBool(streamId, state ~= nil and state.autoEngaged or false)
    streamWriteBool(streamId, state ~= nil and state.diffLockRequested or false)
    streamWriteBool(streamId, state ~= nil and state.diffLockEngaged or false)
    streamWriteBool(streamId, state ~= nil and state.parkBrake or false)
    streamWriteBool(streamId, state ~= nil and state.windupActive or false)
    streamWriteUInt8(streamId, math.floor(sanitizeNumber(state ~= nil and state.windupStress or 0, 0, 0, 1) * 255 + 0.5))
end

function ADS_Drivetrain.readStreamState(vehicle, streamId)
    local hasControl = streamReadBool(streamId)
    local hasCenterDiff = streamReadBool(streamId)
    local externallyManaged = streamReadBool(streamId)
    local parkExternallyManaged = streamReadBool(streamId)
    local driveMode = streamReadUIntN(streamId, 2)
    local autoEngaged = streamReadBool(streamId)
    local diffLockRequested = streamReadBool(streamId)
    local diffLockEngaged = streamReadBool(streamId)
    local parkBrake = streamReadBool(streamId)
    local windupActive = streamReadBool(streamId)
    local windupStress = streamReadUInt8(streamId) / 255

    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then return end
    state.hasControl = hasControl
    state.hasCenterDiff = hasCenterDiff
    state.externallyManaged = externallyManaged
    state.parkExternallyManaged = parkExternallyManaged
    state.driveMode = math.clamp(driveMode, 0, 2)
    state.autoEngaged = autoEngaged
    state.diffLockRequested = diffLockRequested
    state.diffLockEngaged = diffLockEngaged
    state.parkBrake = parkBrake
    state.windupActive = windupActive
    state.windupStress = windupStress
end

function ADS_Drivetrain.saveToXMLFile(vehicle, xmlFile, key)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then return end
    xmlFile:setValue(key .. "#driveMode", state.driveMode)
    xmlFile:setValue(key .. "#diffLockRequested", state.diffLockRequested == true)
    xmlFile:setValue(key .. "#parkBrake", state.parkBrake == true)
end

function ADS_Drivetrain.loadFromSavegame(vehicle, xmlFile, key)
    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then return end
    state.driveMode = math.clamp(math.floor(tonumber(xmlFile:getValue(key .. "#driveMode", state.driveMode)) or state.driveMode), 0, 2)
    state.diffLockRequested = xmlFile:getValue(key .. "#diffLockRequested", state.diffLockRequested) == true
    state.parkBrake = xmlFile:getValue(key .. "#parkBrake", state.parkBrake) == true
end

-- ==========================================================
--                  INPUT ACTION CALLBACKS
-- ==========================================================

function ADS_Drivetrain.actionToggleDriveMode(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not ADS_Drivetrain.getIsAvailable(vehicle)
            or not ADS_Drivetrain.getHasCenterDifferential(vehicle) then
        return
    end
    ADS_Drivetrain.cycleDriveMode(vehicle)
end

function ADS_Drivetrain.actionToggleDiffLock(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not ADS_Drivetrain.getIsAvailable(vehicle) then return end
    ADS_Drivetrain.toggleDiffLock(vehicle)
end

function ADS_Drivetrain.actionToggleParkBrake(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not getConfig().PARKBRAKE_ENABLED then return end
    ADS_Drivetrain.toggleParkBrake(vehicle)
end

function ADS_Drivetrain.registerActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_AdvancedDamageSystem
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    spec.drivetrainActionEvents = spec.drivetrainActionEvents or {}
    vehicle:clearActionEventsTable(spec.drivetrainActionEvents)

    if not isActiveForInputIgnoreSelection then return end
    if spec.isExcludedVehicle then return end

    if getConfig().ENABLED and not state.externallyManaged then
        if state.hasCenterDiff or not state.layoutAnalyzed then
            local _, modeEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.ADS_TOGGLE_4WD, vehicle,
                ADS_Drivetrain.actionToggleDriveMode, false, true, false, true, nil)
            if modeEventId ~= nil then
                g_inputBinding:setActionEventText(modeEventId, g_i18n:getText("input_ADS_TOGGLE_4WD"))
                g_inputBinding:setActionEventTextPriority(modeEventId, GS_PRIO_LOW)
                g_inputBinding:setActionEventTextVisibility(modeEventId, true)
            end
        end

        local _, lockEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.ADS_TOGGLE_DIFFLOCK, vehicle,
            ADS_Drivetrain.actionToggleDiffLock, false, true, false, true, nil)
        if lockEventId ~= nil then
            g_inputBinding:setActionEventText(lockEventId, g_i18n:getText("input_ADS_TOGGLE_DIFFLOCK"))
            g_inputBinding:setActionEventTextPriority(lockEventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(lockEventId, true)
        end
    end

    if getConfig().PARKBRAKE_ENABLED and not state.parkExternallyManaged then
        local _, parkEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.ADS_TOGGLE_PARKBRAKE, vehicle,
            ADS_Drivetrain.actionToggleParkBrake, false, true, false, true, nil)
        if parkEventId ~= nil then
            g_inputBinding:setActionEventText(parkEventId, g_i18n:getText("input_ADS_TOGGLE_PARKBRAKE"))
            g_inputBinding:setActionEventTextPriority(parkEventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(parkEventId, true)
        end
    end
end

function ADS_Drivetrain.getIsParkBrakeEngaged(vehicle)
    if not getConfig().PARKBRAKE_ENABLED then return false end
    local state = ADS_Drivetrain.getState(vehicle)
    return state ~= nil and state.parkBrake == true and not state.parkExternallyManaged
end
