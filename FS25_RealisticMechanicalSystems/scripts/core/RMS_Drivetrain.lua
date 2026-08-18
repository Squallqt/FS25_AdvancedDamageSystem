-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Drivetrain system: drive mode, differential lock, windup and park brake
RMS_Drivetrain = RMS_Drivetrain or {}

-- drive modes, in cycling order
RMS_Drivetrain.MODE = {
    TWO_WD  = 0,
    FOUR_WD = 1,
    AUTO    = 2
}

-- l10n key of each drive mode
RMS_Drivetrain.MODE_L10N = {
    [0] = "rms_drivetrain_mode_4x2",
    [1] = "rms_drivetrain_mode_4wd",
    [2] = "rms_drivetrain_mode_auto"
}

local LOCKED_MIN_TORQUE_RATIO = 0.1
local LOCKED_MAX_TORQUE_RATIO = 0.9
local LOCKED_TORQUE_DEAD_ZONE = 0.02
local LOCKED_WHEEL_SPEED_FILTER = 0.2
local TRACK_STEER_INPUT_EPSILON = 0.001
local DEBUG_SAMPLE_INTERVAL_MS = 400
local DEBUG_RATIO_MIN_SPEED = 0.05
local DEBUG_RATIO_MAX = 99

local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber

---Returns the drivetrain configuration section
-- @return table config drivetrain configuration
local function getConfig()
    return RMS_Config.DRIVETRAIN
end

local evConfigCache = { diff = nil, park = nil, nextReadTime = -math.huge }

---Reads the differential and park brake switches of the other mod, re-reading every ten seconds
-- @return table cache cached switch values
local function readEnhancedVehicleSettings()
    local now = g_time or 0
    if evConfigCache.diff ~= nil and now < evConfigCache.nextReadTime then
        return evConfigCache
    end
    evConfigCache.nextReadTime = now + 10000 -- re-read every 10s (menu changes)

    local diffEnabled, parkEnabled = true, true
    local path = getUserProfileAppPath() .. "modSettings/FS25_EnhancedVehicle/FS25_EnhancedVehicle_v1.xml"
    if fileExists(path) then
        local xml = loadXMLFile("rmsEvConfig", path)
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

---Tells whether the other drivetrain mod is loaded
-- @param table? vehicle vehicle
-- @return boolean isLoaded true when it is present
local function getIsEnhancedVehicleLoaded(vehicle)
    if rawget(_G, "FS25_EnhancedVehicle") ~= nil then
        return true
    end
    if g_modIsLoaded ~= nil and g_modIsLoaded["FS25_EnhancedVehicle"] == true then
        return true
    end
    return vehicle ~= nil and vehicle.vData ~= nil and vehicle.vData.is ~= nil
end

---Tells whether another mod already owns the differential control
-- @param table? vehicle vehicle
-- @return boolean isManaged true when RMS must stay out
function RMS_Drivetrain.isExternallyManaged(vehicle)
    local ev = rawget(_G, "FS25_EnhancedVehicle")
    if ev ~= nil and ev.functionDiffIsEnabled ~= nil then
        return ev.functionDiffIsEnabled == true
    end

    if getIsEnhancedVehicleLoaded(vehicle) then
        return readEnhancedVehicleSettings().diff
    end

    return false
end

---Tells whether another mod already owns the park brake
-- @param table? vehicle vehicle
-- @return boolean isManaged true when RMS must stay out
function RMS_Drivetrain.isParkBrakeExternallyManaged(vehicle)
    local ev = rawget(_G, "FS25_EnhancedVehicle")
    if ev ~= nil and ev.functionParkingBrakeIsEnabled ~= nil then
        return ev.functionParkingBrakeIsEnabled == true
    end

    if getIsEnhancedVehicleLoaded(vehicle) then
        return readEnhancedVehicleSettings().park
    end

    return false
end

---Returns the store categories of a vehicle
-- @param table? vehicle vehicle
-- @return table? categoryNames store category names
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

---Tells whether the vehicle sits in one of the excluded road categories
-- @param table? vehicle vehicle
-- @return boolean isRoadVehicle true for an excluded category
function RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
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

---Tells whether a wheel steers, on its rotation range or its rotation speed
-- @param table? wheel wheel
-- @return boolean isSteerable true for a steering wheel
function RMS_Drivetrain.getIsWheelSteerable(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if physics == nil then return false end
    local rotMin = tonumber(physics.rotMin) or 0
    local rotMax = tonumber(physics.rotMax) or 0
    if math.abs(rotMax - rotMin) > 0.01 then
        return true
    end
    return math.abs(tonumber(physics.rotSpeed) or 0) > 0.001
end

---Returns the longitudinal position of a wheel
-- @param table? wheel wheel
-- @return float positionZ local z position
local function getWheelLocalZ(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if physics == nil then return 0 end
    return tonumber(physics.positionZ) or (physics.netInfo ~= nil and tonumber(physics.netInfo.z)) or 0
end

---Returns the axle speed of a wheel, 0 without a wheel shape
-- @param table? wheel wheel
-- @return float speed axle speed
local function getWheelAxleSpeed(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if wheel == nil or wheel.node == nil or physics == nil or not physics.wheelShapeCreated then
        return 0
    end
    return tonumber(getWheelShapeAxleSpeed(wheel.node, physics.wheelShape)) or 0
end

---Walks a differential subtree and collects the wheel indices it drives
-- @param table differentials differential list
-- @param integer diffIndex0 zero based differential index
-- @param table wheelIndices collected wheel indices, filled in place
-- @param table visited differentials already walked
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

---Returns how steerable an axle is and where it sits along the vehicle
-- @param table vehicle vehicle
-- @param table wheelIndices wheel indices of the axle
-- @return float steerableRatio share of steering wheels
-- @return float averageZ mean longitudinal position
local function getAxleScore(vehicle, wheelIndices)
    local steerableCount, zSum, count = 0, 0, 0
    for _, wheelIndex in ipairs(wheelIndices) do
        local wheel = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(wheelIndex) or nil
        if wheel ~= nil then
            count = count + 1
            zSum = zSum + getWheelLocalZ(wheel)
            if RMS_Drivetrain.getIsWheelSteerable(wheel) then
                steerableCount = steerableCount + 1
            end
        end
    end
    if count == 0 then
        return 0, 0
    end
    return steerableCount / count, zSum / count
end

---Tells whether the vehicle runs on two crawler tracks and nothing else
-- @param table vehicle vehicle
-- @return boolean isTwinTrack true for a twin track machine
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

---Analyses the differential graph and returns the center, primary axle and lockable differentials
-- @param table vehicle vehicle
-- @return table? layout drivetrain layout, nil without differentials
function RMS_Drivetrain.buildLayout(vehicle)
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

---Creates the drivetrain state on the vehicle spec
-- @param table? vehicle vehicle
function RMS_Drivetrain.initSpec(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.drivetrain = {
        layout = nil,
        layoutAnalyzed = false,
        hasControl = false,
        hasCenterDiff = false,
        externallyManaged = false,
        parkExternallyManaged = false,
        driveMode = RMS_Drivetrain.MODE.TWO_WD,
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

---Returns the drivetrain state of a vehicle
-- @param table? vehicle vehicle
-- @return table? state drivetrain state
function RMS_Drivetrain.getState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec ~= nil and spec.drivetrain or nil
end

---Tells whether the drivetrain system runs on this vehicle
-- @param table? vehicle vehicle
-- @return boolean isAvailable true when RMS drives it
function RMS_Drivetrain.getIsAvailable(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    return state ~= nil
        and state.hasControl == true
        and not state.externallyManaged
        and getConfig().ENABLED
end

---Tells whether the vehicle carries a center differential
-- @param table? vehicle vehicle
-- @return boolean hasCenter true with a center differential
function RMS_Drivetrain.getHasCenterDifferential(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    return state ~= nil and state.hasCenterDiff == true
end

---Builds the layout on first use and caches it on the state
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @return boolean hasLayout true once a usable layout is cached
local function ensureLayout(vehicle, state)
    if state.layoutAnalyzed then
        return state.layout ~= nil
    end
    local spec_wheels = vehicle.spec_wheels
    if spec_wheels == nil or spec_wheels.wheels == nil or #spec_wheels.wheels == 0 then
        return false
    end
    state.layoutAnalyzed = true

    if RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        state.layout = nil
        state.hasControl = false
        state.hasCenterDiff = false
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
        return false
    end

    state.layout = RMS_Drivetrain.buildLayout(vehicle)
    state.hasControl = state.layout ~= nil
    state.hasCenterDiff = state.layout ~= nil and state.layout.centerIdx0 ~= nil
    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
    return state.layout ~= nil
end

---Tells whether all wheels are driven right now, single axle machines always being engaged
-- @param table state drivetrain state
-- @return boolean fourWheelDrive true while every axle is driven
local function getEffectiveFourWheelDrive(state)
    if state.layout == nil or state.layout.centerIdx0 == nil then
        return true -- single-axle machines are always "engaged"
    end
    if state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        return true
    elseif state.driveMode == RMS_Drivetrain.MODE.AUTO then
        return state.autoEngaged
    end
    return false
end

---Tells whether the engine locks the center differential itself
-- @param table layout drivetrain layout
-- @param boolean fourWheelDrive true while every axle is driven
-- @return boolean nativeLock true when the engine handles the lock
local function getIsNativeLock(layout, fourWheelDrive)
    return fourWheelDrive and layout.centerIdx0 ~= nil
end

---Returns the speed ratio of a differential for the current lock state
-- @param table original original differential values
-- @param boolean lockEngaged true while the lock is engaged
-- @param boolean nativeLock true when the engine handles the lock
-- @return float maxSpeedRatio target speed ratio
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

---Builds the differential graph to install, resolving each output to a wheel shape or a child
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param boolean useFullGraph true to keep every axle, false to drive the primary one only
-- @return table? plan differentials to install
-- @return table? sourceToNative source index to installed index map
local function buildDifferentialPlan(vehicle, state, useFullGraph)
    local layout = state.layout
    local lockEngaged = state.diffLockEngaged == true
    local nativeLock = getIsNativeLock(layout, useFullGraph)
    local plan = {}
    local sourceToNative = {}
    local visiting = {}

    ---Adds a source differential to the plan, its children first, and returns its installed index
    -- @param integer sourceIdx0 zero based source differential index
    -- @return integer? nativeIdx0 index in the plan, nil when an output cannot be resolved
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

        ---Resolves one differential output to a wheel shape or to a child differential index
        -- @param integer outputIndex wheel index or differential index
        -- @param boolean outputIsWheel true when the output is a wheel
        -- @return integer? output resolved output, nil when unavailable
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

---Replaces the engine differential graph with the planned one
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param boolean useFullGraph true to keep every axle
-- @return boolean installed true when the graph was replaced
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

---Puts the original differential graph back on the vehicle
-- @param table vehicle vehicle
-- @param table state drivetrain state
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

---Installs the differential graph matching the current drive mode
-- @param table vehicle vehicle
-- @param boolean? force true to reinstall even when nothing changed
function RMS_Drivetrain.applyState(vehicle, force)
    if not vehicle.isServer then return end

    local state = RMS_Drivetrain.getState(vehicle)
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

---Shifts the torque ratio toward the slower output of a locked axle differential
-- @param table original original differential values
-- @param float speed1 peripheral speed of the first output
-- @param float speed2 peripheral speed of the second output
-- @param float gearRatio current gear ratio
-- @return float torqueRatio torque ratio to apply
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

---Returns the two output speeds of a differential, wheel speeds being low pass filtered
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param integer differentialIdx0 zero based differential index
-- @param table wheelSpeeds wheel speeds computed so far
-- @param integer depth recursion depth
-- @return float speed1 speed of the first output
-- @return float speed2 speed of the second output
local function getDifferentialOutputSpeeds(vehicle, state, differentialIdx0, wheelSpeeds, depth)
    local layout = state.layout
    if depth > layout.differentialCount then
        return 0, 0
    end

    local differential = layout.originals[differentialIdx0]
    if differential == nil then
        return 0, 0
    end

    ---Returns the speed of one output, a wheel being filtered and a child being the mean of its own outputs
    -- @param integer outputIndex wheel index or differential index
    -- @param boolean outputIsWheel true when the output is a wheel
    -- @return float speed peripheral speed
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

---Pushes the torque and speed ratios of every differential for the current lock state
-- @param table vehicle vehicle
-- @param table state drivetrain state
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

---Reapplies the managed differential graph after the engine rebuilds vehicle physics
-- @param table vehicle vehicle
-- @param function superFunc overwritten function
-- @return boolean success true when the vehicle was added to physics
function RMS_Drivetrain.addToPhysics(vehicle, superFunc)
    local success = superFunc(vehicle)
    if not success then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then
        return true
    end

    state._wasAddedToPhysics = vehicle.isAddedToPhysics == true

    if vehicle.isServer
        and not spec.isExcludedVehicle
        and getConfig().ENABLED
        and not RMS_Drivetrain.isExternallyManaged(vehicle)
        and ensureLayout(vehicle, state) then
        RMS_Drivetrain.applyState(vehicle, true)
        applyDifferentialLock(vehicle, state)
    end

    return true
end

---Sets the drive mode, the differential lock request and the park brake, and replicates them
-- @param table vehicle vehicle
-- @param integer? driveMode drive mode
-- @param boolean? diffLockRequested true to ask for the lock
-- @param boolean? parkBrake true to engage the park brake
-- @param boolean? noEventSend no event send
function RMS_Drivetrain.setDrivetrainState(vehicle, driveMode, diffLockRequested, parkBrake, noEventSend)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end

    driveMode = math.clamp(math.floor(tonumber(driveMode) or state.driveMode), 0, 2)
    if not getConfig().ALLOW_AUTO_MODE and driveMode == RMS_Drivetrain.MODE.AUTO then
        driveMode = RMS_Drivetrain.MODE.FOUR_WD
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
        if state.driveMode ~= RMS_Drivetrain.MODE.AUTO then
            state.autoEngaged = false
            state._autoConditionTimer = 0
        end
        if changed then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
        end
    elseif changed then
        RMS_DrivetrainEvent.sendEvent(vehicle, noEventSend)
    end
end

---Sets the park brake
-- @param table vehicle vehicle
-- @param boolean engaged true to engage it
-- @param boolean? noEventSend no event send
function RMS_Drivetrain.setParkBrake(vehicle, engaged, noEventSend)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, engaged, noEventSend)
end

---Steps to the next drive mode, skipping the automatic one when it is disabled
-- @param table vehicle vehicle
function RMS_Drivetrain.cycleDriveMode(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil or not state.hasCenterDiff then return end

    local nextMode
    if state.driveMode == RMS_Drivetrain.MODE.TWO_WD then
        nextMode = RMS_Drivetrain.MODE.FOUR_WD
    elseif state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        nextMode = getConfig().ALLOW_AUTO_MODE and RMS_Drivetrain.MODE.AUTO or RMS_Drivetrain.MODE.TWO_WD
    else
        nextMode = RMS_Drivetrain.MODE.TWO_WD
    end

    RMS_Drivetrain.setDrivetrainState(vehicle, nextMode, state.diffLockRequested, state.parkBrake)
end

---Toggles the differential lock request
-- @param table vehicle vehicle
function RMS_Drivetrain.toggleDiffLock(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil or not state.hasControl then return end
    RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, not state.diffLockRequested, state.parkBrake)
end

---Toggles the park brake
-- @param table vehicle vehicle
function RMS_Drivetrain.toggleParkBrake(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    RMS_Drivetrain.setParkBrake(vehicle, not state.parkBrake)
end

---Engages all wheel drive on slip or on load at low speed, and releases it with hysteresis
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param table spec vehicle spec
-- @param float dt time since last call in ms
local function updateAutoMode(vehicle, state, spec, dt)
    if state.driveMode ~= RMS_Drivetrain.MODE.AUTO then return end

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

---Engages the lock below the release speed and drops it above
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param float dt time since last call in ms
local function updateDiffLockState(vehicle, state, dt)
    local C = getConfig()
    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)

    if state.diffLockRequested then
        if state.diffLockEngaged then
            if speed > C.DIFFLOCK_AUTO_RELEASE_SPEED then
                state.diffLockEngaged = false
                RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, false, state.parkBrake, false)
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

---Tells whether the vehicle is turning, twin tracks reacting to the steering input instead
-- @param table vehicle vehicle
-- @return boolean isTurning true while turning
function RMS_Drivetrain.getIsTurning(vehicle)
    local steerState = vehicle.spec_RealisticMechanicalSystems.chassisSteerState
    local steeringAngle = steerState.angleMagnitude
    if steeringAngle > getConfig().WINDUP_STEER_THRESHOLD then
        return true
    end

    return getIsTwinTrack(vehicle)
        and steerState.inputMagnitude > TRACK_STEER_INPUT_EPSILON
end

---Accumulates drivetrain windup while turning with the lock or all wheel drive engaged
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param table spec vehicle spec
-- @param float dt time since last call in ms
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
            vehicle:applyInstantDamageToSystem(RealisticMechanicalSystems.SYSTEMS.TRANSMISSION, C.WINDUP_INSTANT_DAMAGE)
            state._windupDamageLatched = true
            state.windupStress = 0.5
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.WEAR)
        end
    end

    if state.windupStress > 0 and isWindingUp then
        state.windupWearFactor = state.windupStress * C.WINDUP_WEAR_MULTIPLIER * windupFactor
    else
        state.windupWearFactor = 0
    end

end

---Marks the park brake notification as pending
-- @param table state drivetrain state
local function notifyParkBrakeChange(state)
    if state._lastNotifiedPark ~= state.parkBrake then
        if state._lastNotifiedPark ~= nil then
            local key = state.parkBrake and "rms_drivetrain_notify_park_on" or "rms_drivetrain_notify_park_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
            RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
        end
        state._lastNotifiedPark = state.parkBrake
    end
end

---Shows the drive mode, lock and park brake messages to the driving player
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param float dt time since last call in ms
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
            local modeText = g_i18n:getText(RMS_Drivetrain.MODE_L10N[state.driveMode] or "rms_drivetrain_mode_4wd")
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, string.format(g_i18n:getText("rms_drivetrain_notify_mode"), modeText))
            RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
        end
        state._lastNotifiedMode = state.driveMode
    end

    if driveModeChanged or state.driveMode ~= RMS_Drivetrain.MODE.AUTO then
        state._lastNotifiedAutoEngaged = state.autoEngaged
    elseif state._lastNotifiedAutoEngaged ~= state.autoEngaged then
        if state._lastNotifiedAutoEngaged ~= nil then
            local modeKey = state.autoEngaged and "rms_drivetrain_mode_4wd" or "rms_drivetrain_mode_4x2"
            local modeText = g_i18n:getText(modeKey)
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, string.format(g_i18n:getText("rms_drivetrain_notify_mode"), modeText))
            RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
        end
        state._lastNotifiedAutoEngaged = state.autoEngaged
    end

    if state._lastNotifiedLock ~= state.diffLockEngaged then
        if state._lastNotifiedLock ~= nil then
            local key = state.diffLockEngaged and "rms_drivetrain_notify_lock_on" or "rms_drivetrain_notify_lock_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
            RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
        end
        state._lastNotifiedLock = state.diffLockEngaged
    end

    notifyParkBrakeChange(state)

    state._parkWarningCooldown = math.max((state._parkWarningCooldown or 0) - dt, 0)
    if state.parkBrake and not getConfig().PARKBRAKE_AUTO_MODE and vehicle.spec_drivable ~= nil then
        local axisForward = math.abs(tonumber(vehicle.spec_drivable.axisForward) or 0)
        if axisForward > 0.2 and state._parkWarningCooldown <= 0 then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_drivetrain_warning_parkbrake"), 2000)
            state._parkWarningCooldown = 4000
        end
    end

    state._windupWarningCooldown = math.max((state._windupWarningCooldown or 0) - dt, 0)
    local C = getConfig()
    local warningThreshold = state.diffLockEngaged and C.WINDUP_WARNING_THRESHOLD or C.WINDUP_4WD_WARNING_THRESHOLD
    if state.windupActive and state.windupStress > warningThreshold and state._windupWarningCooldown <= 0 then
        local warningKey = state.diffLockEngaged and "rms_drivetrain_warning_difflock_windup" or "rms_drivetrain_warning_4wd_windup"
        g_currentMission:showBlinkingWarning(g_i18n:getText(warningKey), 2500)
        state._windupWarningCooldown = 5000
    end
end

---Holds the vehicle still while the park brake is engaged, and releases it automatically
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param float dt time since last call in ms
local function updateParkBrakeState(vehicle, state, dt)
    if not getConfig().PARKBRAKE_ENABLED or state.parkExternallyManaged then
        if state.parkBrake then
            RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        end
        return
    end

    if state.parkBrake and vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        return
    end

    if getConfig().PARKBRAKE_AUTO_MODE and not state.parkBrake then
        local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
        if not vehicle:getIsControlled() and not vehicle:getIsAIActive() and speed < 1.0 then
            RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, true, false)
        end
    end

    if getConfig().PARKBRAKE_AUTO_MODE and state.parkBrake and vehicle:getIsControlled() then
        local axisForward = vehicle.spec_drivable ~= nil and math.abs(tonumber(vehicle.spec_drivable.axisForward) or 0) or 0
        if axisForward > 0.2 then
            RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        end
    end
end

---Samples the wheel speed ratio of each axle differential and the ratio currently enforced
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param table dbg drivetrain debug data
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

---Fills the drivetrain debug data
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param table spec vehicle spec
local function updateDebugData(vehicle, state, spec)
    if not RMS_Config.DEBUG or spec.debugData == nil or spec.debugData.drivetrain == nil then
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

---Runs the whole drivetrain update: automatic mode, lock, windup, park brake and notifications
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
function RMS_Drivetrain.updateDrivetrain(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    if not vehicle.isServer then
        updateLocalNotifications(vehicle, state, dt)
        return
    end

    if not ensureLayout(vehicle, state) then return end

    local externallyManaged = RMS_Drivetrain.isExternallyManaged(vehicle)
    local parkExternallyManaged = RMS_Drivetrain.isParkBrakeExternallyManaged(vehicle)
    local managementChanged = state.externallyManaged ~= externallyManaged
        or state.parkExternallyManaged ~= parkExternallyManaged
    if managementChanged then
        state.externallyManaged = externallyManaged
        state.parkExternallyManaged = parkExternallyManaged
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
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
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
        end
        return
    end

    if state.driveMode == RMS_Drivetrain.MODE.AUTO and not getConfig().ALLOW_AUTO_MODE then
        RMS_Drivetrain.setDrivetrainState(vehicle, RMS_Drivetrain.MODE.FOUR_WD, state.diffLockRequested, state.parkBrake, false)
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
    RMS_Drivetrain.applyState(vehicle, physicsRestored)
    applyDifferentialLock(vehicle, state)

    local windupQuantized = math.floor(sanitizeNumber(state.windupStress, 0, 0, 1) * 255 + 0.5)
    local physicalStateChanged = prevAutoEngaged ~= state.autoEngaged
        or prevDiffLockEngaged ~= state.diffLockEngaged
        or prevWindupActive ~= state.windupActive
        or prevWindupQuantized ~= windupQuantized
    if physicalStateChanged then
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
    end

    updateLocalNotifications(vehicle, state, dt)
    updateDebugData(vehicle, state, spec)
end

---Returns the wear factor the accumulated windup contributes
-- @param table vehicle vehicle
-- @return float factor windup wear factor
function RMS_Drivetrain.getWindupWearFactor(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return 0 end
    return sanitizeNumber(state.windupWearFactor, 0, 0, 100)
end

---Writes the drive mode, the lock request and the park brake
-- @param table vehicle vehicle
-- @param integer streamId streamId
function RMS_Drivetrain.writeStreamState(vehicle, streamId)
    local state = RMS_Drivetrain.getState(vehicle)
    streamWriteBool(streamId, state ~= nil and state.hasControl or false)
    streamWriteBool(streamId, state ~= nil and state.hasCenterDiff or false)
    streamWriteBool(streamId, state ~= nil and state.externallyManaged or false)
    streamWriteBool(streamId, state ~= nil and state.parkExternallyManaged or false)
    streamWriteUIntN(streamId, state ~= nil and state.driveMode or RMS_Drivetrain.MODE.FOUR_WD, 2)
    streamWriteBool(streamId, state ~= nil and state.autoEngaged or false)
    streamWriteBool(streamId, state ~= nil and state.diffLockRequested or false)
    streamWriteBool(streamId, state ~= nil and state.diffLockEngaged or false)
    streamWriteBool(streamId, state ~= nil and state.parkBrake or false)
    streamWriteBool(streamId, state ~= nil and state.windupActive or false)
    streamWriteUInt8(streamId, math.floor(sanitizeNumber(state ~= nil and state.windupStress or 0, 0, 0, 1) * 255 + 0.5))
end

---Reads the drive mode, the lock request and the park brake
-- @param table vehicle vehicle
-- @param integer streamId streamId
function RMS_Drivetrain.readStreamState(vehicle, streamId)
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

    local state = RMS_Drivetrain.getState(vehicle)
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

---Writes the drivetrain state to the savegame
-- @param table vehicle vehicle
-- @param XMLFile xmlFile XMLFile instance
-- @param string key xml key
function RMS_Drivetrain.saveToXMLFile(vehicle, xmlFile, key)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    xmlFile:setValue(key .. "#driveMode", state.driveMode)
    xmlFile:setValue(key .. "#diffLockRequested", state.diffLockRequested == true)
    xmlFile:setValue(key .. "#parkBrake", state.parkBrake == true)
end

---Reads the drivetrain state from the savegame
-- @param table vehicle vehicle
-- @param XMLFile xmlFile XMLFile instance
-- @param string key xml key
function RMS_Drivetrain.loadFromSavegame(vehicle, xmlFile, key)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    state.driveMode = math.clamp(math.floor(tonumber(xmlFile:getValue(key .. "#driveMode", state.driveMode)) or state.driveMode), 0, 2)
    state.diffLockRequested = xmlFile:getValue(key .. "#diffLockRequested", state.diffLockRequested) == true
    state.parkBrake = xmlFile:getValue(key .. "#parkBrake", state.parkBrake) == true
end

---Input action stepping to the next drive mode
-- @param table vehicle vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleDriveMode(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not RMS_Drivetrain.getIsAvailable(vehicle)
            or not RMS_Drivetrain.getHasCenterDifferential(vehicle) then
        return
    end
    RMS_Drivetrain.cycleDriveMode(vehicle)
end

---Input action toggling the differential lock
-- @param table vehicle vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleDiffLock(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not RMS_Drivetrain.getIsAvailable(vehicle) then return end
    RMS_Drivetrain.toggleDiffLock(vehicle)
end

---Input action toggling the park brake
-- @param table vehicle vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleParkBrake(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not getConfig().PARKBRAKE_ENABLED then return end
    RMS_Drivetrain.toggleParkBrake(vehicle)
end

---Registers the drivetrain input actions
-- @param table vehicle vehicle
-- @param boolean isActiveForInputIgnoreSelection true if active for input
function RMS_Drivetrain.registerActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    spec.drivetrainActionEvents = spec.drivetrainActionEvents or {}
    vehicle:clearActionEventsTable(spec.drivetrainActionEvents)

    local isActiveForInputWithAI = vehicle.getIsActiveForInput ~= nil
        and vehicle:getIsActiveForInput(false, true)
    if not isActiveForInputIgnoreSelection and not isActiveForInputWithAI then return end
    if spec.isExcludedVehicle then return end

    if getConfig().ENABLED and not state.externallyManaged then
        if state.hasCenterDiff or not state.layoutAnalyzed then
            local _, modeEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.RMS_TOGGLE_4WD, vehicle,
                RMS_Drivetrain.actionToggleDriveMode, false, true, false, true, nil)
            if modeEventId ~= nil then
                g_inputBinding:setActionEventText(modeEventId, g_i18n:getText("input_RMS_TOGGLE_4WD"))
                g_inputBinding:setActionEventTextPriority(modeEventId, GS_PRIO_LOW)
                g_inputBinding:setActionEventTextVisibility(modeEventId, true)
            end
        end

        local _, lockEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.RMS_TOGGLE_DIFFLOCK, vehicle,
            RMS_Drivetrain.actionToggleDiffLock, false, true, false, true, nil)
        if lockEventId ~= nil then
            g_inputBinding:setActionEventText(lockEventId, g_i18n:getText("input_RMS_TOGGLE_DIFFLOCK"))
            g_inputBinding:setActionEventTextPriority(lockEventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(lockEventId, true)
        end
    end

    if isActiveForInputIgnoreSelection
        and getConfig().PARKBRAKE_ENABLED
        and not state.parkExternallyManaged then
        local _, parkEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.RMS_TOGGLE_PARKBRAKE, vehicle,
            RMS_Drivetrain.actionToggleParkBrake, false, true, false, true, nil)
        if parkEventId ~= nil then
            g_inputBinding:setActionEventText(parkEventId, g_i18n:getText("input_RMS_TOGGLE_PARKBRAKE"))
            g_inputBinding:setActionEventTextPriority(parkEventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(parkEventId, true)
        end
    end
end

---Tells whether the park brake is engaged
-- @param table? vehicle vehicle
-- @return boolean isEngaged true while it holds the vehicle
function RMS_Drivetrain.getIsParkBrakeEngaged(vehicle)
    if not getConfig().PARKBRAKE_ENABLED then return false end
    local state = RMS_Drivetrain.getState(vehicle)
    return state ~= nil and state.parkBrake == true and not state.parkExternallyManaged
end
