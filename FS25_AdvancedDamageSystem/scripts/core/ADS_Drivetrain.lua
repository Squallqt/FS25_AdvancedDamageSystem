-- =====================================================================================
--  ADS_Drivetrain
--  Realistic 4WD / differential lock management for motorized ADS vehicles.
--
--  Responsibilities (single role: drivetrain physics state + windup stress model):
--   * Analyze the differential topology declared by vehicle.xml (spec_motorized.differentials)
--     without any hardcoded indices: axle differentials connect two wheels, the center
--     differential connects two other differentials.
--   * Build the active driveline with the native differential graph bindings. No vanilla
--     function is overwritten or monkeypatched.
--   * Drive modes: 4x2 (primary axle graph only), 4WD (full XML graph), AUTO (engages the
--     assist axle on slip / low speed under load, releases it on the road).
--   * Differential locks: active native torque balancing across the driven outputs, with
--     automatic release above a speed threshold.
--   * Driveline windup model: driving in 4WD or with locked differentials while
--     steering on a high-grip surface accumulates stress and damages the transmission.
--
--  Multiplayer: physics runs on the server. Player commands travel through
--  ADS_DrivetrainEvent; the resulting state is replicated with the dedicated
--  adsDirtyFlag_drivetrain update-stream group.
--
--  Third-party compatibility:
--   * FS25_EnhancedVehicle: if its own differential control is enabled the ADS module
--     stands down entirely for every vehicle (both would fight over the same physics
--     differentials). Checked dynamically, no load-order requirement.
--   * CVT addons (spec_CVTaddon): fully compatible, this module never touches motor
--     ratios, only differential torque distribution.
-- =====================================================================================

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

local LOCKED_AXLE_SPEED_RATIO = 1.1
local LOCKED_MIN_TORQUE_RATIO = 0.3
local LOCKED_MAX_TORQUE_RATIO = 0.7
local LOCKED_WHEEL_SPEED_FILTER = 0.08

local function sanitizeNumber(value, fallback, minValue, maxValue)
    if AdvancedDamageSystem ~= nil and AdvancedDamageSystem.sanitizeNumber ~= nil then
        return AdvancedDamageSystem.sanitizeNumber(value, fallback, minValue, maxValue)
    end
    local sanitized = tonumber(value) or tonumber(fallback) or 0
    if minValue ~= nil then sanitized = math.max(sanitized, minValue) end
    if maxValue ~= nil then sanitized = math.min(sanitized, maxValue) end
    return sanitized
end

-- Lua locals only exist below their declaration: getConfig must precede every helper
-- that calls it (a late declaration silently resolves to nil at call time).
local function getConfig()
    return ADS_Config.DRIVETRAIN
end

--- EnhancedVehicle owns the physics differentials when its diff feature is enabled,
--  and its own parking brake when that feature is enabled. Mods load in separate
--  script environments, so EV's global table is not always visible from here. When
--  it is not, EV's persistent settings file (the same file its in-game menu writes)
--  is the authoritative source for both toggles.
local evConfigCache = { diff = nil, park = nil, nextReadTime = -math.huge }

local function readEnhancedVehicleSettings()
    local now = g_time or 0
    if evConfigCache.diff ~= nil and now < evConfigCache.nextReadTime then
        return evConfigCache
    end
    evConfigCache.nextReadTime = now + 10000 -- re-read every 10s (menu changes)

    -- EV ships with both functions enabled by default.
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
    -- Shared-state global visible: read EV's live flag directly.
    local ev = rawget(_G, "FS25_EnhancedVehicle")
    if ev ~= nil and ev.functionDiffIsEnabled ~= nil then
        return ev.functionDiffIsEnabled == true
    end

    if getIsEnhancedVehicleLoaded(vehicle) then
        return readEnhancedVehicleSettings().diff
    end

    return false
end

--- EV's own parking brake takes precedence over ours when its feature is enabled.
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

--- Collects every wheel (by wheelIndex) driven through a differential subtree.
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

--- Scores an axle group: steerable wheels and average local Z position decide front vs rear.
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

--- Builds spec.drivetrain.layout from spec_motorized.differentials.
--  Pure data analysis (no physics calls): valid on server and client.
--  Returns nil when the vehicle has no usable differential setup.
function ADS_Drivetrain.buildLayout(vehicle)
    local spec_motorized = vehicle.spec_motorized
    local differentials = spec_motorized ~= nil and spec_motorized.differentials or nil
    if differentials == nil or next(differentials) == nil then
        return nil
    end

    local layout = {
        differentialCount = #differentials,
        originals = {},           -- immutable XML differential descriptors by 0-based index
        centerIdx0 = nil,         -- inter-axle differential (engine index, 0-based)
        -- The disengageable axle is the STEERED one: front axle on a tractor (MFWD),
        -- rear assist axle on a combine or a sprayer. The primary axle is the fixed one.
        primaryIdx0 = nil,        -- fixed/primary axle differential
        engageableWheelIndices = {},
        primaryWheelIndices = {},
        lockableIdx0 = {},        -- axle differentials that can be locked
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

    if layout.centerIdx0 ~= nil then
        local center = differentials[layout.centerIdx0 + 1]
        local out1Idx0 = tonumber(center.diffIndex1) or 0
        local out2Idx0 = tonumber(center.diffIndex2) or 0

        local out1Wheels, out2Wheels = {}, {}
        collectWheelIndices(differentials, out1Idx0, out1Wheels, {})
        collectWheelIndices(differentials, out2Idx0, out2Wheels, {})

        local steer1, z1 = getAxleScore(vehicle, out1Wheels)
        local steer2, z2 = getAxleScore(vehicle, out2Wheels)

        -- The engageable (disengageable) axle is the steered one, regardless of whether
        -- it sits at the front (tractor MFWD) or at the rear (combine assist axle).
        -- Fallback for fully articulated machines: the front output (+Z) disengages.
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

        -- Lockable differentials = every wheel-to-wheel differential. Axle membership
        -- follows the center diff subtree the wheels belong to, which stays correct
        -- for tandem-axle layouts with nested inter-axle diffs.
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
        -- Single driven axle (no center differential): 4WD toggle unavailable,
        -- but the axle differential itself remains lockable.
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

--- Called from AdvancedDamageSystem:onLoad.
function ADS_Drivetrain.initSpec(vehicle)
    local spec = vehicle.spec_AdvancedDamageSystem
    spec.drivetrain = {
        layout = nil,                       -- server only: physics layout (differentials are not loaded on clients)
        layoutAnalyzed = false,
        hasControl = false,                 -- capability flag, resolved on the server, replicated to clients
        hasCenterDiff = false,              -- capability flag, replicated to clients
        externallyManaged = false,          -- EV owns the diffs; resolved on the server, replicated to clients
        parkExternallyManaged = false,      -- EV owns the parking brake; resolved on the server, replicated to clients
        driveMode = ADS_Drivetrain.MODE.TWO_WD,
        autoEngaged = false,
        diffLockRequested = false,
        diffLockEngaged = false,
        parkBrake = false,
        windupStress = 0,
        windupWearFactor = 0,
        windupActive = false,
        _windupDamageLatched = false,
        _appliedMode = nil,                 -- last state pushed to the physics engine
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

--- True when the drive mode / diff lock feature can act on this vehicle.
--  hasControl and externallyManaged are resolved on the server (differentials and
--  the EV settings file live there) and replicated through the drivetrain sync group,
--  which keeps server and client decisions consistent.
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
        return false -- wheels not ready yet, retry next update
    end
    state.layoutAnalyzed = true

    if ADS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        state.layout = nil
        state.hasControl = false
        state.hasCenterDiff = false
        return false
    end

    state.layout = ADS_Drivetrain.buildLayout(vehicle)
    state.hasControl = state.layout ~= nil
    state.hasCenterDiff = state.layout ~= nil and state.layout.centerIdx0 ~= nil
    return state.layout ~= nil
end

-- ==========================================================
--              PHYSICS APPLICATION (SERVER)
-- ==========================================================

--- Effective mode as applied to the physics: AUTO resolves to engaged/disengaged.
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

--- Builds a validated native differential plan without touching the active physics graph.
local function buildDifferentialPlan(vehicle, layout, useFullGraph)
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
            maxSpeedRatio = original.maxSpeedRatio
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

    local plan, sourceToNative = buildDifferentialPlan(vehicle, state.layout, useFullGraph)
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

--- Pushes the requested drive mode to the engine differentials. Server only.
--  Idempotent: rebuilds the native graph only when the driven topology changes.
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

local function getLockedDifferentialRatios(original, speed1, speed2, isAxleDifferential, gearRatio)
    local torqueRatio = original.torqueRatio
    local maxSpeedRatio = isAxleDifferential and LOCKED_AXLE_SPEED_RATIO or original.maxSpeedRatio

    if gearRatio < 0 then
        speed1 = -speed1
        speed2 = -speed2
    end

    if speed1 < 0.1389 and speed2 < 0.1389 then
        return torqueRatio, maxSpeedRatio
    end

    if not (-0.2778 < speed1 and speed1 < 90 and -0.2778 < speed2 and speed2 < 90) then
        return torqueRatio, math.max(maxSpeedRatio, LOCKED_AXLE_SPEED_RATIO)
    end

    if speed1 < speed2 then
        local speedRatio = math.max(speed1, 0) / speed2
        torqueRatio = 1 - speedRatio * (1 - torqueRatio)
        maxSpeedRatio = math.max(maxSpeedRatio, 1 + (LOCKED_AXLE_SPEED_RATIO - 1) * (1 - speedRatio))
    elseif speed2 < speed1 then
        local speedRatio = math.max(speed2, 0) / speed1
        torqueRatio = torqueRatio * speedRatio
        maxSpeedRatio = math.max(maxSpeedRatio, 1 + (LOCKED_AXLE_SPEED_RATIO - 1) * (1 - speedRatio))
    end

    if math.abs(torqueRatio - original.torqueRatio) < 0.05 then
        torqueRatio = original.torqueRatio
    end

    return math.clamp(torqueRatio, LOCKED_MIN_TORQUE_RATIO, LOCKED_MAX_TORQUE_RATIO), maxSpeedRatio
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
            local torqueRatio = original.torqueRatio
            local maxSpeedRatio = original.maxSpeedRatio
            if lockEngaged then
                local speed1, speed2 = getDifferentialOutputSpeeds(vehicle, state, sourceIdx0, wheelSpeeds, 1)
                local isAxleDifferential = original.diffIndex1IsWheel and original.diffIndex2IsWheel
                torqueRatio, maxSpeedRatio = getLockedDifferentialRatios(
                    original,
                    speed1,
                    speed2,
                    isAxleDifferential,
                    gearRatio
                )
            end

            updateDifferential(spec_motorized.motorizedNode, nativeIdx0, torqueRatio, maxSpeedRatio)
        end
    end

    state._appliedLock = lockEngaged
end

-- ==========================================================
--                 COMMAND SETTERS (MP-SAFE)
-- ==========================================================

--- Central MP-safe setter. Runs on both sides; forwards through ADS_DrivetrainEvent.
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

    if changed then
        ADS_DrivetrainEvent.sendEvent(vehicle, driveMode, diffLockRequested, parkBrake, noEventSend)
    end

    if vehicle.isServer then
        if state.driveMode ~= ADS_Drivetrain.MODE.AUTO then
            state.autoEngaged = false
            state._autoConditionTimer = 0
        end
        -- The engagement decision (speed gate) happens in the server update; requesting
        -- the lock at excessive speed simply arms it until conditions allow.
        local spec = vehicle.spec_AdvancedDamageSystem
        if changed and spec ~= nil and spec.adsDirtyFlag_drivetrain ~= nil then
            vehicle:raiseDirtyFlags(spec.adsDirtyFlag_drivetrain)
        end
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

--- AUTO mode decision, evaluated on the server at ON_UPDATE cadence.
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

--- Diff lock engagement gate + realistic automatic release (server).
local function updateDiffLockState(vehicle, state, dt)
    local C = getConfig()
    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)

    -- An AI worker would never drive around with locked differentials.
    if state.diffLockRequested and vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, false, state.parkBrake, false)
        return
    end

    if state.diffLockRequested then
        if state.diffLockEngaged then
            -- Realistic auto-release above the mechanical threshold.
            if speed > C.DIFFLOCK_AUTO_RELEASE_SPEED then
                state.diffLockEngaged = false
                ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, false, state.parkBrake, false)
            end
        else
            -- Dog clutches only engage below the threshold.
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
    return (tonumber(steerState ~= nil and steerState.angleMagnitude or 0) or 0) > getConfig().WINDUP_STEER_THRESHOLD
end

--- Driveline windup: 4WD / locked differentials + steering + grip = accumulated stress (server).
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
    local surfaceFactor = state.diffLockEngaged and 1 or sanitizeNumber(spec.avgGroundSurfaceFactor, 0, 0, 1)

    local isWindingUp = speed > 1.0
        and steering > C.WINDUP_STEER_THRESHOLD
        and surfaceFactor > 0
        and friction >= C.WINDUP_FRICTION_THRESHOLD

    state.windupActive = isWindingUp

    if isWindingUp then
        local stressLimit = state.diffLockEngaged and 1.0 or math.max(tonumber(C.WINDUP_4WD_MAX_STRESS) or 0, 0)
        local steerFactor = math.min(steering / 0.5, 1.0)
        local frictionFactor = math.min(friction / math.max(C.WINDUP_FRICTION_THRESHOLD, 0.001), 1.5)
        local speedFactor = math.min(speed / 10.0, 1.0)
        local rate = C.WINDUP_ACCUMULATION_RATE * steerFactor * frictionFactor * speedFactor * surfaceFactor * windupFactor
        if state.windupStress > stressLimit then
            state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE, stressLimit)
        else
            state.windupStress = math.min(state.windupStress + (dt / 1000) * rate, stressLimit)
        end
    else
        -- Low grip or straight driving lets the strain dissipate through the tires.
        local releaseBoost = 1.0 + (1.0 - surfaceFactor) + math.max(1.2 - friction, 0)
        state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE * releaseBoost, 0)
    end

    if state.windupStress <= 0 then
        state._windupDamageLatched = false
    end

    -- Peak load: apply one impact per continuous locked-windup episode.
    if state.diffLockEngaged and state.windupStress >= 1.0 and not state._windupDamageLatched then
        local transmissionSystem = spec.systems ~= nil and spec.systems.transmission or nil
        if transmissionSystem ~= nil and transmissionSystem.enabled == true and vehicle.applyInstantDamageToSystem ~= nil then
            vehicle:applyInstantDamageToSystem(AdvancedDamageSystem.SYSTEMS.TRANSMISSION, C.WINDUP_INSTANT_DAMAGE)
            state._windupDamageLatched = true
            state.windupStress = 0.5
            if spec.adsDirtyFlag_wear ~= nil then
                vehicle:raiseDirtyFlags(spec.adsDirtyFlag_wear)
            end
        end
    end

    -- Continuous transmission wear factor consumed by updateTransmissionSystem.
    if state.windupStress > 0 and isWindingUp then
        state.windupWearFactor = state.windupStress * C.WINDUP_WEAR_MULTIPLIER * windupFactor
    else
        state.windupWearFactor = 0
    end

end

--- Fires the park brake side notification when its state changed since last check.
local function notifyParkBrakeChange(state)
    if state._lastNotifiedPark ~= state.parkBrake then
        if state._lastNotifiedPark ~= nil then
            local key = state.parkBrake and "ads_drivetrain_notify_park_on" or "ads_drivetrain_notify_park_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
            if ADS_Main ~= nil and ADS_Main.samples ~= nil and ADS_Main.samples.notification2D ~= nil then
                g_soundManager:playSample(ADS_Main.samples.notification2D)
            end
        end
        state._lastNotifiedPark = state.parkBrake
    end
end

--- Local player feedback (client side of the machine currently controlled).
local function updateLocalNotifications(vehicle, state, dt)
    if g_dedicatedServerInfo ~= nil then return end
    local isControlled = g_currentMission ~= nil
        and vehicle:getIsActiveForInput(true)
        and not vehicle:getIsAIActive()
    if not isControlled then
        state._lastNotifiedMode = state.driveMode
        state._lastNotifiedAutoEngaged = state.autoEngaged
        state._lastNotifiedLock = state.diffLockEngaged

        -- Grace window so the park brake notification survives losing control.
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
            if ADS_Main ~= nil and ADS_Main.samples ~= nil and ADS_Main.samples.notification2D ~= nil then
                g_soundManager:playSample(ADS_Main.samples.notification2D)
            end
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
            if ADS_Main ~= nil and ADS_Main.samples ~= nil and ADS_Main.samples.notification2D ~= nil then
                g_soundManager:playSample(ADS_Main.samples.notification2D)
            end
        end
        state._lastNotifiedAutoEngaged = state.autoEngaged
    end

    if state._lastNotifiedLock ~= state.diffLockEngaged then
        if state._lastNotifiedLock ~= nil then
            local key = state.diffLockEngaged and "ads_drivetrain_notify_lock_on" or "ads_drivetrain_notify_lock_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
            if ADS_Main ~= nil and ADS_Main.samples ~= nil and ADS_Main.samples.notification2D ~= nil then
                g_soundManager:playSample(ADS_Main.samples.notification2D)
            end
        end
        state._lastNotifiedLock = state.diffLockEngaged
    end

    notifyParkBrakeChange(state)

    -- Trying to drive off against the engaged parking brake (manual mode only).
    state._parkWarningCooldown = math.max((state._parkWarningCooldown or 0) - dt, 0)
    if state.parkBrake and not getConfig().PARKBRAKE_AUTO_MODE and vehicle.spec_drivable ~= nil then
        local axisForward = math.abs(tonumber(vehicle.spec_drivable.axisForward) or 0)
        if axisForward > 0.2 and state._parkWarningCooldown <= 0 then
            g_currentMission:showBlinkingWarning(g_i18n:getText("ads_drivetrain_warning_parkbrake"), 2000)
            state._parkWarningCooldown = 4000
        end
    end

    -- Preventive warning while 4WD or a locked differential winds up the driveline.
    state._windupWarningCooldown = math.max((state._windupWarningCooldown or 0) - dt, 0)
    local C = getConfig()
    local warningThreshold = state.diffLockEngaged and C.WINDUP_WARNING_THRESHOLD or C.WINDUP_4WD_WARNING_THRESHOLD
    if state.windupActive and state.windupStress > warningThreshold and state._windupWarningCooldown <= 0 then
        local warningKey = state.diffLockEngaged and "ads_drivetrain_warning_difflock_windup" or "ads_drivetrain_warning_4wd_windup"
        g_currentMission:showBlinkingWarning(g_i18n:getText(warningKey), 2500)
        state._windupWarningCooldown = 5000
    end
end

--- Automatic parking brake: engages when the operator leaves the machine (server).
local function updateParkBrakeState(vehicle, state, dt)
    if not getConfig().PARKBRAKE_ENABLED or state.parkExternallyManaged then
        if state.parkBrake then
            ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        end
        return
    end

    -- AI workers release the brake before driving off.
    if state.parkBrake and vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        return
    end

    -- Auto engage when the operator leaves the standing machine.
    if getConfig().PARKBRAKE_AUTO_MODE and not state.parkBrake then
        local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
        if not vehicle:getIsControlled() and not vehicle:getIsAIActive() and speed < 1.0 then
            ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, true, false)
        end
    end

    -- Auto release on throttle input.
    if getConfig().PARKBRAKE_AUTO_MODE and state.parkBrake and vehicle:getIsControlled() then
        local axisForward = vehicle.spec_drivable ~= nil and math.abs(tonumber(vehicle.spec_drivable.axisForward) or 0) or 0
        if axisForward > 0.2 then
            ADS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, false, false)
        end
    end
end

--- Main entry point, called from AdvancedDamageSystem:onUpdate at ON_UPDATE cadence.
function ADS_Drivetrain.updateDrivetrain(vehicle, dt)
    local spec = vehicle.spec_AdvancedDamageSystem
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    -- Clients never see spec_motorized.differentials (server-only data): they run on
    -- the replicated capability flags and only handle local player feedback.
    if not vehicle.isServer then
        updateLocalNotifications(vehicle, state, dt)
        return
    end

    if not ensureLayout(vehicle, state) then return end

    -- EV ownership is a server decision, replicated so client HUD/inputs stay coherent.
    local externallyManaged = ADS_Drivetrain.isExternallyManaged(vehicle)
    local parkExternallyManaged = ADS_Drivetrain.isParkBrakeExternallyManaged(vehicle)
    if state.externallyManaged ~= externallyManaged or state.parkExternallyManaged ~= parkExternallyManaged then
        state.externallyManaged = externallyManaged
        state.parkExternallyManaged = parkExternallyManaged
        if spec.adsDirtyFlag_drivetrain ~= nil then
            vehicle:raiseDirtyFlags(spec.adsDirtyFlag_drivetrain)
        end
    end

    if not getConfig().ENABLED or externallyManaged then
        -- Feature off or EV owns the diffs: full stand-by. When EV is active it manages
        -- the drivetrain entirely on its own (physics, behavior and consequences); ADS
        -- does not touch the differentials nor run any drivetrain damage model.
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
            if spec.adsDirtyFlag_drivetrain ~= nil then
                vehicle:raiseDirtyFlags(spec.adsDirtyFlag_drivetrain)
            end
        end
        return
    end

    -- Settings may forbid AUTO after a vehicle was saved in AUTO: fall back to 4WD.
    if state.driveMode == ADS_Drivetrain.MODE.AUTO and not getConfig().ALLOW_AUTO_MODE then
        ADS_Drivetrain.setDrivetrainState(vehicle, ADS_Drivetrain.MODE.FOUR_WD, state.diffLockRequested, state.parkBrake, false)
    end

    -- Differentials are recreated from vehicle.xml whenever the vehicle re-enters
    -- physics: reapply our state on the rising edge.
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

    -- Replicate physical state changes (engagement + windup) to the clients.
    local windupQuantized = math.floor(sanitizeNumber(state.windupStress, 0, 0, 1) * 255 + 0.5)
    if (prevAutoEngaged ~= state.autoEngaged
        or prevDiffLockEngaged ~= state.diffLockEngaged
        or prevWindupActive ~= state.windupActive
        or prevWindupQuantized ~= windupQuantized)
        and spec.adsDirtyFlag_drivetrain ~= nil then
        vehicle:raiseDirtyFlags(spec.adsDirtyFlag_drivetrain)
    end

    updateLocalNotifications(vehicle, state, dt)

    if ADS_Config.DEBUG and spec.debugData ~= nil and spec.debugData.drivetrain ~= nil then
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
end

--- Consumed by AdvancedDamageSystem:updateTransmissionSystem as an additive wear factor.
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
    if not ADS_Drivetrain.getIsAvailable(vehicle) then return end
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

--- Registers the drivetrain vehicle actions. Called from onRegisterActionEvents.
function ADS_Drivetrain.registerActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_AdvancedDamageSystem
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    spec.drivetrainActionEvents = spec.drivetrainActionEvents or {}
    vehicle:clearActionEventsTable(spec.drivetrainActionEvents)

    if not isActiveForInputIgnoreSelection then return end
    if spec.isExcludedVehicle then return end

    -- Drive mode / diff lock: only without EV. Capability flags are replicated, but may
    -- not be received yet right after joining: register anyway, callbacks re-validate.
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

    -- Parking brake: available on every ADS vehicle, unless EV's own parking brake
    -- feature is enabled (same take-over principle as the differential control).
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

--- Consumed by ADS_Breakdowns.updateVehiclePhysics: anchors the vehicle when the
--  parking brake is engaged (the operator input path, like a real park position).
function ADS_Drivetrain.getIsParkBrakeEngaged(vehicle)
    if not getConfig().PARKBRAKE_ENABLED then return false end
    local state = ADS_Drivetrain.getState(vehicle)
    return state ~= nil and state.parkBrake == true and not state.parkExternallyManaged
end
